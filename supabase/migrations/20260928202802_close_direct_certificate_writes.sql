-- Issuance and revocation belong to a future trusted backend. A verified
-- institution alone cannot authorize client writes without PDF/hash validation.
-- Preserve the SELECT policy and every existing row, constraint and trigger.
DROP POLICY IF EXISTS certificates_insert_authorized ON public.certificates;
DROP POLICY IF EXISTS certificates_update_authorized ON public.certificates;

-- Supabase's default grants include writes and TRUNCATE. RLS alone is not
-- sufficient: TRUNCATE is not subject to row policies. No column-level grants
-- exist in the preceding migrations; API roles inherit no other database roles.
REVOKE ALL PRIVILEGES ON TABLE public.certificates FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.certificates TO authenticated;

-- Close the same destructive path on tables referenced by certificates.
-- Keep their existing business DML grants and RLS policies unchanged.
REVOKE TRUNCATE, REFERENCES, TRIGGER
    ON TABLE public.profiles, public.institutions, public.institution_members
    FROM PUBLIC, anon, authenticated;

-- This legacy trigger remains as a transition guard, not a client operation.
-- Trigger execution itself does not require the caller's EXECUTE privilege.
REVOKE ALL ON FUNCTION certichain_private.protect_certificate_update()
    FROM PUBLIC, anon, authenticated;

-- Trusted migration/backend privileges are not granted to clients or changed
-- here. No RPC, Storage flow, issuance or revocation endpoint is introduced.
