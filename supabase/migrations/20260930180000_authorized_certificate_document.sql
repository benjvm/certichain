-- 7C: narrow technical read. Does not widen table or Storage client permissions.
CREATE FUNCTION public.authorize_certificate_document(p_certificate uuid, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    result jsonb;
BEGIN
    SELECT jsonb_build_object('path', c.document_path, 'hash', c.document_hash)
    INTO result
    FROM public.certificates AS c
    JOIN public.certificate_issuance_operations AS op ON op.id = c.issuance_operation_id
    WHERE c.id = p_certificate
        AND op.status = 'completed' AND op.certificate_id = c.id
        AND op.target_certificate_id = c.id AND op.institution_id = c.institution_id
        AND op.holder_id = c.holder_id AND op.actor_id = c.issued_by
        AND op.stored_hash = c.document_hash AND op.pdf_hash = c.document_hash
        AND c.document_path = c.institution_id::text || '/' || c.id::text || '.pdf'
        AND EXISTS (SELECT 1 FROM auth.users AS u WHERE u.id = p_actor
            AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous, false)
            AND (u.banned_until IS NULL OR u.banned_until <= clock_timestamp()))
        AND (c.holder_id = p_actor OR EXISTS (
            SELECT 1 FROM public.institution_members AS m
            JOIN public.institutions AS i ON i.id = m.institution_id
            WHERE m.institution_id = c.institution_id AND m.user_id = p_actor
                AND m.role IN ('owner', 'admin', 'issuer') AND i.verification_status = 'verified'
        ));
    -- Foreign, missing, legacy and inaccessible certificates share one result.
    RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.authorize_certificate_document(uuid, uuid)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.authorize_certificate_document(uuid, uuid) TO service_role;
