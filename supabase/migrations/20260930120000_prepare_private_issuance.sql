-- Phase 7A: persistent reservations and integrity for certificates linked to an
-- issuance operation. Existing certificates are deliberately left untouched.
CREATE TABLE public.certificate_issuance_operations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions (id) ON DELETE RESTRICT,
    actor_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
    holder_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
    idempotency_key uuid NOT NULL,
    request_fingerprint text NOT NULL,
    pdf_hash text NOT NULL,
    target_certificate_id uuid NOT NULL DEFAULT gen_random_uuid(),
    stored_hash text,
    certificate_id uuid,
    status text NOT NULL DEFAULT 'reserved',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT issuance_key_per_institution UNIQUE (institution_id, idempotency_key),
    CONSTRAINT issuance_target_unique UNIQUE (target_certificate_id),
    CONSTRAINT issuance_fingerprint_format CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
    CONSTRAINT issuance_pdf_hash_format CHECK (pdf_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT issuance_stored_hash_format CHECK (stored_hash IS NULL OR stored_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT issuance_status_valid CHECK (status IN
        ('reserved', 'uploading', 'finalizing', 'completed', 'cleanup_pending', 'failed')),
    CONSTRAINT issuance_status_consistent CHECK (
        (status IN ('reserved', 'uploading', 'cleanup_pending', 'failed')
            AND certificate_id IS NULL AND stored_hash IS NULL)
        OR (status = 'finalizing' AND certificate_id IS NULL
            AND stored_hash IS NOT NULL)
        OR (status = 'completed' AND certificate_id IS NOT NULL
            AND certificate_id = target_certificate_id
            AND stored_hash IS NOT NULL)
    ),
    CONSTRAINT issuance_certificate_once UNIQUE (certificate_id),
    CONSTRAINT issuance_certificate_identity UNIQUE
        (id, target_certificate_id, institution_id, actor_id, holder_id, stored_hash)
);

CREATE INDEX issuance_actor_idx ON public.certificate_issuance_operations (actor_id);
CREATE INDEX issuance_holder_idx ON public.certificate_issuance_operations (holder_id);
CREATE INDEX issuance_reconcile_idx ON public.certificate_issuance_operations (status, updated_at)
    WHERE status <> 'completed';

ALTER TABLE public.certificates
    ADD COLUMN issuance_operation_id uuid;
ALTER TABLE public.certificates
    ADD CONSTRAINT certificates_issuance_integrity CHECK (
        issuance_operation_id IS NULL OR (
            document_hash IS NOT NULL AND document_hash ~ '^[0-9a-f]{64}$'
            AND document_path IS NOT NULL
            AND document_path = institution_id::text || '/' || id::text || '.pdf'
        )
    );
ALTER TABLE public.certificates
    ADD CONSTRAINT certificates_issuance_identity UNIQUE
        (id, institution_id, issued_by, holder_id, issuance_operation_id);
ALTER TABLE public.certificates
    ADD CONSTRAINT certificates_issuance_operation_fk FOREIGN KEY
        (issuance_operation_id, id, institution_id, issued_by, holder_id, document_hash)
        REFERENCES public.certificate_issuance_operations
        (id, target_certificate_id, institution_id, actor_id, holder_id, stored_hash)
        ON DELETE RESTRICT;
ALTER TABLE public.certificate_issuance_operations
    ADD CONSTRAINT issuance_certificate_fk FOREIGN KEY
        (certificate_id, institution_id, actor_id, holder_id, id)
        REFERENCES public.certificates
        (id, institution_id, issued_by, holder_id, issuance_operation_id)
        ON DELETE RESTRICT;

-- Keep the reservation's identity and published result stable across retries.
CREATE FUNCTION certichain_private.protect_issuance_operation_update()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF ROW(NEW.id, NEW.institution_id, NEW.actor_id, NEW.holder_id,
           NEW.idempotency_key, NEW.request_fingerprint, NEW.pdf_hash,
           NEW.target_certificate_id, NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.id, OLD.institution_id, OLD.actor_id, OLD.holder_id,
           OLD.idempotency_key, OLD.request_fingerprint, OLD.pdf_hash,
           OLD.target_certificate_id, OLD.created_at)
       OR (OLD.status = 'completed' AND ROW(NEW.status, NEW.stored_hash, NEW.certificate_id)
           IS DISTINCT FROM ROW(OLD.status, OLD.stored_hash, OLD.certificate_id)) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Issuance operation identity or result is immutable';
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;
CREATE TRIGGER issuance_operation_protect_update
BEFORE UPDATE ON public.certificate_issuance_operations
FOR EACH ROW EXECUTE FUNCTION certichain_private.protect_issuance_operation_update();
REVOKE ALL ON FUNCTION certichain_private.protect_issuance_operation_update()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION certichain_private.protect_issued_certificate_update()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF OLD.issuance_operation_id IS DISTINCT FROM NEW.issuance_operation_id
       OR (OLD.issuance_operation_id IS NOT NULL AND
           ROW(NEW.id, NEW.holder_id, NEW.institution_id, NEW.issued_by,
               NEW.title, NEW.description, NEW.credential_code,
               NEW.document_path, NEW.document_hash, NEW.issued_at,
               NEW.expires_at, NEW.created_at)
           IS DISTINCT FROM
           ROW(OLD.id, OLD.holder_id, OLD.institution_id, OLD.issued_by,
               OLD.title, OLD.description, OLD.credential_code,
               OLD.document_path, OLD.document_hash, OLD.issued_at,
               OLD.expires_at, OLD.created_at)) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Issued certificate is immutable';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER certificates_issued_protect_update
BEFORE UPDATE ON public.certificates
FOR EACH ROW EXECUTE FUNCTION certichain_private.protect_issued_certificate_update();
REVOKE ALL ON FUNCTION certichain_private.protect_issued_certificate_update()
    FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.certificate_issuance_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.certificate_issuance_operations FROM PUBLIC, anon, authenticated;
-- No client policies or issuance RPC: only trusted backend SQL can reserve or finish.

-- Bucket metadata is versioned here as well as in config.toml for local startup.
-- Never create or delete storage.objects via SQL.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('certificates', 'certificates', false, 8388608, ARRAY['application/pdf']::text[])
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Storage has broad table grants. Restrictive policies keep this bucket closed
-- to API roles even if another permissive policy is added later.
CREATE POLICY certificates_objects_no_client_select ON storage.objects
    AS RESTRICTIVE FOR SELECT TO anon, authenticated
    USING (bucket_id <> 'certificates');
CREATE POLICY certificates_objects_no_client_insert ON storage.objects
    AS RESTRICTIVE FOR INSERT TO anon, authenticated
    WITH CHECK (bucket_id <> 'certificates');
CREATE POLICY certificates_objects_no_client_update ON storage.objects
    AS RESTRICTIVE FOR UPDATE TO anon, authenticated
    USING (bucket_id <> 'certificates') WITH CHECK (bucket_id <> 'certificates');
CREATE POLICY certificates_objects_no_client_delete ON storage.objects
    AS RESTRICTIVE FOR DELETE TO anon, authenticated
    USING (bucket_id <> 'certificates');
