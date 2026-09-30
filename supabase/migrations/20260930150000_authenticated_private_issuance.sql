-- 7B: service-only transactions. Storage is always outside these transactions.
ALTER TABLE public.certificate_issuance_operations
    ADD COLUMN title text,
    ADD COLUMN description text,
    ADD COLUMN expires_at timestamptz,
    ADD COLUMN lease_token uuid,
    ADD COLUMN lease_until timestamptz;

CREATE FUNCTION certichain_private.protect_issuance_metadata()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF ROW(NEW.title, NEW.description, NEW.expires_at)
       IS DISTINCT FROM ROW(OLD.title, OLD.description, OLD.expires_at) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Issuance metadata is immutable';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER issuance_metadata_immutable BEFORE UPDATE
ON public.certificate_issuance_operations FOR EACH ROW
EXECUTE FUNCTION certichain_private.protect_issuance_metadata();
REVOKE ALL ON FUNCTION certichain_private.protect_issuance_metadata()
    FROM PUBLIC, anon, authenticated, service_role;

-- Caller already holds the institution lock. No metadata/claims authorize actors.
CREATE FUNCTION certichain_private.authorize_issuance(p_institution uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.institutions AS i
        JOIN public.institution_members AS m ON m.institution_id = i.id
        JOIN auth.users AS u ON u.id = m.user_id
        WHERE i.id = p_institution AND i.verification_status = 'verified'
        AND m.user_id = p_actor AND m.role IN ('owner', 'admin', 'issuer')
        AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous, false)
        AND (u.banned_until IS NULL OR u.banned_until <= clock_timestamp())) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'issuance_forbidden';
    END IF;
END;
$$;

-- MVP recipient: confirmed, non-anonymous, non-banned Auth identity and holder
-- profile. Called only after actor authorization; never expose profile lookup.
CREATE FUNCTION certichain_private.check_issuance_holder(p_holder uuid)
RETURNS void LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    PERFORM 1 FROM auth.users WHERE id = p_holder AND deleted_at IS NULL
        AND email_confirmed_at IS NOT NULL AND NOT coalesce(is_anonymous, false)
        AND (banned_until IS NULL OR banned_until <= clock_timestamp()) FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'holder_ineligible';
    END IF;
    PERFORM 1 FROM public.profiles WHERE id = p_holder AND role = 'holder' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'holder_ineligible';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION certichain_private.authorize_issuance(uuid, uuid),
    certichain_private.check_issuance_holder(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.reserve_certificate_issuance(
    p_institution uuid, p_actor uuid, p_holder uuid, p_key uuid,
    p_fingerprint text, p_pdf_hash text, p_title text,
    p_description text DEFAULT NULL, p_expires timestamptz DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    op public.certificate_issuance_operations;
BEGIN
    -- Same parent-first lock order as phase 6. A stale isolation snapshot aborts
    -- when concurrent membership mutations write the parent.
    PERFORM 1 FROM public.institutions WHERE id = p_institution FOR UPDATE;
    PERFORM certichain_private.authorize_issuance(p_institution, p_actor);
    SELECT * INTO op FROM public.certificate_issuance_operations
        WHERE institution_id = p_institution AND idempotency_key = p_key FOR UPDATE;
    IF FOUND THEN
        IF op.actor_id IS DISTINCT FROM p_actor OR op.request_fingerprint IS DISTINCT FROM p_fingerprint
            OR op.pdf_hash IS DISTINCT FROM p_pdf_hash OR op.holder_id IS DISTINCT FROM p_holder THEN
            RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'idempotency_conflict';
        END IF;
        IF op.status = 'completed' THEN
            RETURN jsonb_build_object('status', 'completed', 'certificate_id', op.certificate_id);
        END IF;
        IF op.status IN ('failed', 'cleanup_pending') THEN
            RETURN jsonb_build_object('status', op.status);
        END IF;
        IF op.lease_until > clock_timestamp() THEN
            RETURN jsonb_build_object('status', 'in_progress', 'retry_after', 120);
        END IF;
    END IF;
    IF p_key IS NULL OR p_actor IS NULL OR p_holder IS NULL
        OR p_fingerprint IS NULL OR p_fingerprint !~ '^[0-9a-f]{64}$'
        OR p_pdf_hash IS NULL OR p_pdf_hash !~ '^[0-9a-f]{64}$'
        OR p_title IS NULL OR char_length(p_title) NOT BETWEEN 1 AND 200
        OR btrim(p_title) = '' OR p_title ~ '[[:cntrl:]]'
        OR (p_description IS NOT NULL AND (char_length(p_description) > 4000
            OR p_description ~ '[[:cntrl:]]'))
        OR (p_expires IS NOT NULL AND (p_expires <= clock_timestamp()
            OR p_expires > clock_timestamp() + interval '10 years')) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid_input';
    END IF;
    PERFORM certichain_private.check_issuance_holder(p_holder);
    IF op.id IS NULL THEN
        INSERT INTO public.certificate_issuance_operations
            (institution_id, actor_id, holder_id, idempotency_key, request_fingerprint,
             pdf_hash, title, description, expires_at)
        VALUES (p_institution, p_actor, p_holder, p_key, p_fingerprint,
            p_pdf_hash, p_title, p_description, p_expires) RETURNING * INTO op;
    ELSIF ROW(op.title, op.description, op.expires_at)
        IS DISTINCT FROM ROW(p_title, p_description, p_expires) THEN
        RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'idempotency_conflict';
    END IF;
    UPDATE public.certificate_issuance_operations SET status = 'uploading', stored_hash = NULL,
        lease_token = gen_random_uuid(), lease_until = clock_timestamp() + interval '120 seconds'
        WHERE id = op.id RETURNING * INTO op;
    RETURN jsonb_build_object('status', 'uploading', 'operation_id', op.id,
        'target_certificate_id', op.target_certificate_id, 'lease_token', op.lease_token);
END;
$$;

-- Fenced state transitions. Cleanup is terminal: cleanup_pending/failed cannot
-- return to uploading, so a delete outside SQL cannot race a future publication.
CREATE FUNCTION public.advance_certificate_issuance(
    p_institution uuid, p_operation uuid, p_lease uuid, p_action text,
    p_stored_hash text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    op public.certificate_issuance_operations;
    issuance_time timestamptz;
BEGIN
    PERFORM 1 FROM public.institutions WHERE id = p_institution FOR UPDATE;
    SELECT * INTO op FROM public.certificate_issuance_operations
        WHERE id = p_operation AND institution_id = p_institution FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid_operation';
    END IF;
    IF op.status = 'completed' OR EXISTS (SELECT 1 FROM public.certificates
        WHERE issuance_operation_id = op.id OR
        document_path = op.institution_id::text || '/' || op.target_certificate_id::text || '.pdf') THEN
        IF p_action IN ('cleanup_claim', 'cleanup_check', 'cleanup_done', 'abandon') THEN
            RETURN jsonb_build_object('status', 'protected');
        END IF;
        RAISE EXCEPTION USING ERRCODE = 'PT409', MESSAGE = 'lease_lost';
    END IF;
    IF p_action = 'cleanup_claim' THEN
        IF op.lease_until > clock_timestamp() THEN
            RETURN jsonb_build_object('status', 'in_progress');
        END IF;
        UPDATE public.certificate_issuance_operations SET status = 'cleanup_pending', stored_hash = NULL,
            lease_token = gen_random_uuid(), lease_until = clock_timestamp() + interval '120 seconds'
            WHERE id = op.id RETURNING * INTO op;
        RETURN jsonb_build_object('status', 'cleanup_pending', 'lease_token', op.lease_token,
            'target_certificate_id', op.target_certificate_id);
    END IF;
    IF p_lease IS NULL OR op.lease_token IS DISTINCT FROM p_lease
        OR op.lease_until IS NULL OR op.lease_until <= clock_timestamp() THEN
        RAISE EXCEPTION USING ERRCODE = 'PT409', MESSAGE = 'lease_lost';
    END IF;
    IF p_action = 'abandon' AND op.status IN ('uploading', 'finalizing') THEN
        UPDATE public.certificate_issuance_operations SET status = 'cleanup_pending', stored_hash = NULL,
            lease_until = clock_timestamp() WHERE id = op.id;
        RETURN jsonb_build_object('status', 'cleanup_pending');
    ELSIF p_action = 'cleanup_check' AND op.status = 'cleanup_pending' THEN
        RETURN jsonb_build_object('status', 'cleanup_pending');
    ELSIF p_action = 'cleanup_done' AND op.status = 'cleanup_pending' THEN
        UPDATE public.certificate_issuance_operations SET status = 'failed', lease_until = clock_timestamp()
            WHERE id = op.id;
        RETURN jsonb_build_object('status', 'failed');
    ELSIF p_action = 'validate' AND op.status = 'uploading' THEN
        IF p_stored_hash IS NULL OR p_stored_hash IS DISTINCT FROM op.pdf_hash THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'stored_hash_mismatch';
        END IF;
        UPDATE public.certificate_issuance_operations SET status = 'finalizing', stored_hash = p_stored_hash
            WHERE id = op.id;
        RETURN jsonb_build_object('status', 'finalizing');
    ELSIF p_action = 'publish' AND op.status = 'finalizing' THEN
        PERFORM certichain_private.authorize_issuance(p_institution, op.actor_id);
        PERFORM certichain_private.check_issuance_holder(op.holder_id);
        issuance_time := clock_timestamp();
        IF op.title IS NULL OR (op.expires_at IS NOT NULL AND op.expires_at <= issuance_time) THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid_input';
        END IF;
        INSERT INTO public.certificates (id, institution_id, holder_id, issued_by,
            title, description, expires_at, issued_at, credential_code, status,
            document_path, document_hash, issuance_operation_id)
        VALUES (op.target_certificate_id, op.institution_id, op.holder_id, op.actor_id,
            op.title, op.description, op.expires_at, issuance_time, gen_random_uuid()::text, 'active',
            op.institution_id::text || '/' || op.target_certificate_id::text || '.pdf', op.stored_hash, op.id);
        UPDATE public.certificate_issuance_operations SET status = 'completed',
            certificate_id = target_certificate_id, lease_until = NULL, lease_token = NULL WHERE id = op.id;
        RETURN jsonb_build_object('status', 'completed', 'certificate_id', op.target_certificate_id);
    END IF;
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid_transition';
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_certificate_issuance(uuid, uuid, uuid, uuid, text, text, text, text, timestamptz),
    public.advance_certificate_issuance(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_certificate_issuance(uuid, uuid, uuid, uuid, text, text, text, text, timestamptz),
    public.advance_certificate_issuance(uuid, uuid, uuid, text, text) TO service_role;

