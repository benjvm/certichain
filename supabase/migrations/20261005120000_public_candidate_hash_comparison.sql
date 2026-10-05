-- 8C: single coherent snapshot for v1 projection and candidate comparison.
-- No changes to rows, RLS, table grants or Storage. Expected hash stays private.
CREATE FUNCTION certichain_private.public_certificate_snapshot(p_credential_code text)
RETURNS jsonb LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
    checked timestamptz := clock_timestamp();
    projection jsonb;
BEGIN
    IF p_credential_code IS NULL OR length(p_credential_code) <> 36
        OR p_credential_code !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid_input';
    END IF;
    -- Equality on the existing unique text index; 7B emits canonical lowercase UUIDs.
    SELECT jsonb_build_object('expected_hash', c.document_hash, 'verification', jsonb_build_object(
        'schema_version', '1',
        'result', certichain_private.public_verification_result(
            c.status = 'revoked', c.expires_at, i.verification_status = 'verified', checked),
        'credential_code', c.credential_code, 'title', c.title,
        'issuer', jsonb_build_object('name', i.name),
        'issued_at', c.issued_at, 'expires_at', c.expires_at,
        'checked_at', checked, 'verification_source', 'certichain_registry'))
    INTO projection
    FROM public.certificates AS c
    JOIN public.certificate_issuance_operations AS op ON op.id = c.issuance_operation_id
    JOIN public.institutions AS i ON i.id = c.institution_id
    WHERE c.credential_code = lower(p_credential_code)
        AND op.status = 'completed'
        AND op.certificate_id = c.id AND op.target_certificate_id = c.id
        AND op.institution_id = c.institution_id AND op.holder_id = c.holder_id
        AND op.actor_id = c.issued_by
        AND c.document_hash ~ '^[0-9a-f]{64}$'
        AND c.document_hash = op.stored_hash AND c.document_hash = op.pdf_hash
        AND c.document_path = c.institution_id::text || '/' || c.id::text || '.pdf';
    RETURN coalesce(projection, jsonb_build_object('expected_hash', NULL, 'verification', jsonb_build_object('schema_version', '1', 'result', 'not_found')));
END;
$$;

REVOKE ALL ON FUNCTION certichain_private.public_certificate_snapshot(text) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.lookup_public_certificate(p_credential_code text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
    SELECT certichain_private.public_certificate_snapshot(p_credential_code)->'verification';
$$;
REVOKE ALL ON FUNCTION public.lookup_public_certificate(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_public_certificate(text) TO service_role;

CREATE FUNCTION public.compare_public_certificate_hash(p_credential_code text, p_document_sha256 text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    snapshot jsonb;
    integrity text;
BEGIN
    IF p_document_sha256 IS NULL OR length(p_document_sha256) <> 64
        OR p_document_sha256 !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid_input';
    END IF;
    snapshot := certichain_private.public_certificate_snapshot(p_credential_code);
    integrity := CASE WHEN snapshot->>'expected_hash' IS NULL THEN 'unavailable'
        WHEN snapshot->>'expected_hash' = p_document_sha256 THEN 'match'
        ELSE 'integrity_mismatch' END;
    RETURN jsonb_build_object('schema_version', '1', 'verification', snapshot->'verification', 'file_integrity', integrity);
END;
$$;
REVOKE ALL ON FUNCTION public.compare_public_certificate_hash(text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.compare_public_certificate_hash(text,text) TO service_role;
