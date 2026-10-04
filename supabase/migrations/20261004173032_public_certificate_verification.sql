-- 8A: registry-only public projection; no table/Storage permissions are widened.
CREATE FUNCTION certichain_private.public_verification_result(
    p_revoked boolean, p_expires timestamptz, p_verified boolean, p_checked timestamptz
)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
    SELECT CASE WHEN p_revoked THEN 'revoked'
        WHEN p_expires <= p_checked THEN 'expired'
        WHEN NOT p_verified THEN 'issuer_unavailable'
        ELSE 'valid' END;
$$;
REVOKE ALL ON FUNCTION certichain_private.public_verification_result(boolean,timestamptz,boolean,timestamptz)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.lookup_public_certificate(p_credential_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    checked timestamptz := clock_timestamp();
    projection jsonb;
BEGIN
    IF p_credential_code IS NULL OR length(p_credential_code) <> 36
        OR p_credential_code !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid_input';
    END IF;
    -- Equality on the existing unique text index; 7B emits canonical lowercase UUIDs.
    SELECT jsonb_build_object(
        'schema_version', '1',
        'result', certichain_private.public_verification_result(
            c.status = 'revoked', c.expires_at, i.verification_status = 'verified', checked),
        'credential_code', c.credential_code, 'title', c.title,
        'issuer', jsonb_build_object('name', i.name),
        'issued_at', c.issued_at, 'expires_at', c.expires_at,
        'checked_at', checked, 'verification_source', 'certichain_registry')
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
    RETURN coalesce(projection, jsonb_build_object('schema_version', '1', 'result', 'not_found'));
END;
$$;
REVOKE ALL ON FUNCTION public.lookup_public_certificate(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_public_certificate(text) TO service_role;

-- One reusable row, no IPs, codes, events or client-selected limits.
CREATE TABLE certichain_private.public_verification_budget (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    window_started_at timestamptz NOT NULL,
    used integer NOT NULL CHECK (used BETWEEN 0 AND 60)
);
ALTER TABLE certichain_private.public_verification_budget ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE certichain_private.public_verification_budget FROM PUBLIC, anon, authenticated, service_role;
INSERT INTO certichain_private.public_verification_budget VALUES (true, clock_timestamp(), 0);

CREATE FUNCTION public.consume_public_verification_budget()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET lock_timeout = '2s' AS $$
DECLARE
    budget certichain_private.public_verification_budget%ROWTYPE;
    checked timestamptz;
BEGIN
    SELECT * INTO STRICT budget FROM certichain_private.public_verification_budget
        WHERE singleton FOR UPDATE;
    -- Read time after acquiring the lock, including concurrent callers crossing renewal.
    checked := clock_timestamp();
    IF checked >= budget.window_started_at + interval '60 seconds' THEN
        budget.window_started_at := checked;
        budget.used := 0;
    END IF;
    IF budget.used >= 60 THEN
        RETURN jsonb_build_object('allowed', false, 'retry_after',
            greatest(1, ceil(extract(epoch FROM budget.window_started_at + interval '60 seconds' - checked))::integer));
    END IF;
    UPDATE certichain_private.public_verification_budget
        SET window_started_at = budget.window_started_at, used = budget.used + 1 WHERE singleton;
    RETURN jsonb_build_object('allowed', true, 'retry_after', 0);
END;
$$;
REVOKE ALL ON FUNCTION public.consume_public_verification_budget() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_public_verification_budget() TO service_role;
