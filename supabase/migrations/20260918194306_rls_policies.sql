-- This schema is deliberately absent from the exposed PostgREST schemas.
CREATE SCHEMA certichain_private;
REVOKE ALL ON SCHEMA certichain_private FROM PUBLIC;
GRANT USAGE ON SCHEMA certichain_private TO authenticated;

-- These SECURITY DEFINER functions read only the caller's database-backed
-- authorization state. Their owner must be the migration/table owner so that
-- the lookups do not recurse through policies on the same tables.
CREATE FUNCTION certichain_private.is_platform_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles AS p
        WHERE p.id = auth.uid() AND p.role = 'platform_admin'
    );
$$;

CREATE FUNCTION certichain_private.is_institution_member(p_institution_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.institution_members AS m
        WHERE m.institution_id = p_institution_id AND m.user_id = auth.uid()
    );
$$;

CREATE FUNCTION certichain_private.has_institution_role(
    p_institution_id uuid,
    p_roles public.institution_role[]
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.institution_members AS m
        WHERE m.institution_id = p_institution_id
          AND m.user_id = auth.uid()
          AND m.role = ANY (p_roles)
    );
$$;

REVOKE ALL ON FUNCTION certichain_private.is_platform_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION certichain_private.is_institution_member(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION certichain_private.has_institution_role(uuid, public.institution_role[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION certichain_private.is_platform_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION certichain_private.is_institution_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION certichain_private.has_institution_role(uuid, public.institution_role[]) TO authenticated;

-- RLS chooses eligible rows; triggers protect columns and state transitions.
CREATE FUNCTION certichain_private.protect_profile_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'Profile identity and creation time are immutable';
    END IF;
    IF NEW.role IS DISTINCT FROM OLD.role
       AND NOT certichain_private.is_platform_admin() THEN
        RAISE EXCEPTION 'Only a platform administrator may change a global role';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_protect_update
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION certichain_private.protect_profile_update();

CREATE FUNCTION certichain_private.protect_institution_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'Institution identity and creation time are immutable';
    END IF;
    IF NEW.verification_status IS DISTINCT FROM OLD.verification_status
       AND NOT certichain_private.is_platform_admin() THEN
        RAISE EXCEPTION 'Only a platform administrator may change verification status';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER institutions_protect_update
BEFORE UPDATE ON public.institutions
FOR EACH ROW EXECUTE FUNCTION certichain_private.protect_institution_update();

CREATE FUNCTION certichain_private.protect_certificate_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF certichain_private.is_platform_admin() THEN
        RETURN NEW;
    END IF;

    -- Institution owners/admins may only revoke an active certificate.
    IF OLD.status <> 'active' OR NEW.status <> 'revoked'
       OR ROW(NEW.id, NEW.holder_id, NEW.institution_id, NEW.issued_by,
              NEW.title, NEW.description, NEW.credential_code,
              NEW.document_path, NEW.document_hash, NEW.issued_at,
              NEW.expires_at, NEW.created_at)
          IS DISTINCT FROM
          ROW(OLD.id, OLD.holder_id, OLD.institution_id, OLD.issued_by,
              OLD.title, OLD.description, OLD.credential_code,
              OLD.document_path, OLD.document_hash, OLD.issued_at,
              OLD.expires_at, OLD.created_at) THEN
        RAISE EXCEPTION 'Institution administrators may only revoke certificates';
    END IF;

    -- Do not accept a caller-supplied revocation timestamp.
    NEW.revoked_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER certificates_protect_update
BEFORE UPDATE ON public.certificates
FOR EACH ROW EXECUTE FUNCTION certichain_private.protect_certificate_update();

REVOKE ALL ON FUNCTION certichain_private.protect_profile_update() FROM PUBLIC;
REVOKE ALL ON FUNCTION certichain_private.protect_institution_update() FROM PUBLIC;
REVOKE ALL ON FUNCTION certichain_private.protect_certificate_update() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION certichain_private.protect_profile_update() TO authenticated;
GRANT EXECUTE ON FUNCTION certichain_private.protect_institution_update() TO authenticated;
GRANT EXECUTE ON FUNCTION certichain_private.protect_certificate_update() TO authenticated;

CREATE POLICY profiles_select_authorized ON public.profiles
FOR SELECT TO authenticated
USING (id = (SELECT auth.uid()) OR (SELECT certichain_private.is_platform_admin()));

CREATE POLICY profiles_update_authorized ON public.profiles
FOR UPDATE TO authenticated
USING (id = (SELECT auth.uid()) OR (SELECT certichain_private.is_platform_admin()))
WITH CHECK (id = (SELECT auth.uid()) OR (SELECT certichain_private.is_platform_admin()));

CREATE POLICY institutions_select_authorized ON public.institutions
FOR SELECT TO authenticated
USING (
    certichain_private.is_institution_member(id)
    OR (SELECT certichain_private.is_platform_admin())
);

CREATE POLICY institutions_insert_platform_admin ON public.institutions
FOR INSERT TO authenticated
WITH CHECK ((SELECT certichain_private.is_platform_admin()));

CREATE POLICY institutions_update_authorized ON public.institutions
FOR UPDATE TO authenticated
USING (
    certichain_private.has_institution_role(id, ARRAY['owner', 'admin']::public.institution_role[])
    OR (SELECT certichain_private.is_platform_admin())
)
WITH CHECK (
    certichain_private.has_institution_role(id, ARRAY['owner', 'admin']::public.institution_role[])
    OR (SELECT certichain_private.is_platform_admin())
);

CREATE POLICY institutions_delete_platform_admin ON public.institutions
FOR DELETE TO authenticated
USING ((SELECT certichain_private.is_platform_admin()));

CREATE POLICY institution_members_select_authorized ON public.institution_members
FOR SELECT TO authenticated
USING (
    user_id = (SELECT auth.uid())
    OR certichain_private.has_institution_role(institution_id, ARRAY['owner', 'admin']::public.institution_role[])
    OR (SELECT certichain_private.is_platform_admin())
);

CREATE POLICY institution_members_insert_authorized ON public.institution_members
FOR INSERT TO authenticated
WITH CHECK (
    certichain_private.has_institution_role(institution_id, ARRAY['owner']::public.institution_role[])
    OR (SELECT certichain_private.is_platform_admin())
);

CREATE POLICY institution_members_update_authorized ON public.institution_members
FOR UPDATE TO authenticated
USING (
    certichain_private.has_institution_role(institution_id, ARRAY['owner']::public.institution_role[])
    OR (SELECT certichain_private.is_platform_admin())
)
WITH CHECK (
    certichain_private.has_institution_role(institution_id, ARRAY['owner']::public.institution_role[])
    OR (SELECT certichain_private.is_platform_admin())
);

CREATE POLICY institution_members_delete_authorized ON public.institution_members
FOR DELETE TO authenticated
USING (
    certichain_private.has_institution_role(institution_id, ARRAY['owner']::public.institution_role[])
    OR (SELECT certichain_private.is_platform_admin())
);

CREATE POLICY certificates_select_authorized ON public.certificates
FOR SELECT TO authenticated
USING (
    holder_id = (SELECT auth.uid())
    OR certichain_private.is_institution_member(institution_id)
    OR (SELECT certichain_private.is_platform_admin())
);

CREATE POLICY certificates_insert_authorized ON public.certificates
FOR INSERT TO authenticated
WITH CHECK (
    (
        issued_by = (SELECT auth.uid())
        AND status = 'active'
        AND revoked_at IS NULL
        AND certichain_private.has_institution_role(
            institution_id, ARRAY['owner', 'admin', 'issuer']::public.institution_role[]
        )
    )
    OR (SELECT certichain_private.is_platform_admin())
);

CREATE POLICY certificates_update_authorized ON public.certificates
FOR UPDATE TO authenticated
USING (
    certichain_private.has_institution_role(institution_id, ARRAY['owner', 'admin']::public.institution_role[])
    OR (SELECT certichain_private.is_platform_admin())
)
WITH CHECK (
    certichain_private.has_institution_role(institution_id, ARRAY['owner', 'admin']::public.institution_role[])
    OR (SELECT certichain_private.is_platform_admin())
);

-- No client INSERT/DELETE on profiles, or DELETE on certificates.
-- No policies target anon; public verification will use a restricted interface.
