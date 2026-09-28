-- Phase 6: managed onboarding. No certificate permissions are opened here.
-- Existing installations must remediate invalid/orphaned institutions explicitly.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.institutions AS i
        WHERE NOT EXISTS (
            SELECT 1 FROM public.institution_members AS m
            WHERE m.institution_id = i.id AND m.role = 'owner'
        )
    ) THEN
        RAISE EXCEPTION 'Existing institutions require an owner before applying phase 6';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.institutions
        WHERE NOT (
            name = btrim(name) AND char_length(name) BETWEEN 2 AND 160
            AND name !~ '[[:cntrl:]]' AND name !~ '^[[:space:]]*$'
            AND char_length(slug) BETWEEN 3 AND 80
            AND slug COLLATE "C" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
        ) OR (website IS NOT NULL AND NOT (
            char_length(website) <= 2048 AND website ~ '^https://[^[:space:]]+$'
            AND website !~ '[[:cntrl:]]'
        ))
    ) THEN
        -- Avoid a failing-row constraint DETAIL containing institutional data.
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'Existing institution details require review before applying phase 6';
    END IF;
END;
$$;

ALTER TABLE public.institutions
    ADD CONSTRAINT institutions_name_valid CHECK (
        name = btrim(name) AND char_length(name) BETWEEN 2 AND 160
        AND name !~ '[[:cntrl:]]' AND name !~ '^[[:space:]]*$'
    ),
    ADD CONSTRAINT institutions_slug_valid CHECK (
        char_length(slug) BETWEEN 3 AND 80
        AND slug COLLATE "C" ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    ),
    ADD CONSTRAINT institutions_website_valid CHECK (
        website IS NULL OR (
            char_length(website) <= 2048 AND website ~ '^https://[^[:space:]]+$'
            AND website !~ '[[:cntrl:]]'
        )
    );

-- Global role grants require trusted SQL even when the API caller is an admin.
-- Keep ordinary profile editing and its existing RLS policies.
CREATE OR REPLACE FUNCTION certichain_private.protect_profile_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'Profile identity and creation time are immutable';
    END IF;
    IF NEW.role IS DISTINCT FROM OLD.role AND current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Global roles require trusted administrative SQL';
    END IF;
    RETURN NEW;
END;
$$;

-- Deliberately SECURITY INVOKER: never turns an API call into trusted SQL.
-- A repeated UUID and an expected count protect against wrong targets/stale runs.
CREATE FUNCTION certichain_private.grant_platform_admin(
    p_target uuid, p_confirm_target uuid, p_expected_admin_count integer
)
RETURNS text
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    existing_role public.user_role;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Trusted administrative SQL is required';
    END IF;
    IF p_target IS NULL OR p_confirm_target IS DISTINCT FROM p_target
       OR p_expected_admin_count IS NULL OR p_expected_admin_count < 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Confirm the target identity and expected administrator count';
    END IF;
    LOCK TABLE public.profiles IN SHARE ROW EXCLUSIVE MODE;
    IF (SELECT count(*) FROM public.profiles WHERE role = 'platform_admin') <> p_expected_admin_count THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Administrator count changed; review before retrying';
    END IF;
    PERFORM 1 FROM auth.users WHERE id = p_target FOR KEY SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Target Auth identity and profile must exist';
    END IF;
    SELECT role INTO existing_role FROM public.profiles WHERE id = p_target FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Target Auth identity and profile must exist';
    END IF;
    IF existing_role = 'platform_admin' THEN
        RETURN 'already_platform_admin';
    END IF;
    UPDATE public.profiles SET role = 'platform_admin', updated_at = now() WHERE id = p_target;
    RETURN 'platform_admin_assigned';
END;
$$;
REVOKE ALL ON FUNCTION certichain_private.grant_platform_admin(uuid, uuid, integer)
    FROM PUBLIC, anon, authenticated, service_role;

-- All institution mutations use narrow transactional operations. SELECT is kept
-- unchanged, including anon's existing grant with no eligible rows under RLS.
DROP POLICY institutions_insert_platform_admin ON public.institutions;
DROP POLICY institutions_update_authorized ON public.institutions;
DROP POLICY institutions_delete_platform_admin ON public.institutions;
DROP POLICY institution_members_insert_authorized ON public.institution_members;
DROP POLICY institution_members_update_authorized ON public.institution_members;
DROP POLICY institution_members_delete_authorized ON public.institution_members;
REVOKE INSERT, UPDATE, DELETE ON public.institutions, public.institution_members
    FROM PUBLIC, anon, authenticated;

CREATE FUNCTION certichain_private.prevent_institution_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Institution deletion is disabled; use verification status';
END;
$$;
CREATE TRIGGER institutions_prevent_delete
BEFORE DELETE ON public.institutions
FOR EACH ROW EXECUTE FUNCTION certichain_private.prevent_institution_delete();

-- TRUNCATE bypasses row triggers/RLS and would invalidate the owner invariant.
-- Deny it even for ordinary trusted SQL; schema maintenance remains privileged.
CREATE FUNCTION certichain_private.prevent_institution_truncate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Institution truncation is disabled';
END;
$$;
CREATE TRIGGER institutions_prevent_truncate
BEFORE TRUNCATE ON public.institutions
FOR EACH STATEMENT EXECUTE FUNCTION certichain_private.prevent_institution_truncate();
CREATE TRIGGER institution_members_prevent_truncate
BEFORE TRUNCATE ON public.institution_members
FOR EACH STATEMENT EXECUTE FUNCTION certichain_private.prevent_institution_truncate();

-- Every member mutation writes the parent row, even trusted SQL and FK cascades.
-- This serializes READ COMMITTED operations and forces stale REPEATABLE READ /
-- SERIALIZABLE transactions to abort (40001), preventing snapshot write skew.
CREATE FUNCTION certichain_private.guard_institution_member()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    institution uuid;
BEGIN
    IF TG_OP = 'UPDATE' AND ROW(NEW.id, NEW.institution_id, NEW.user_id, NEW.created_at)
        IS DISTINCT FROM ROW(OLD.id, OLD.institution_id, OLD.user_id, OLD.created_at) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Membership identity is immutable';
    END IF;
    institution := CASE WHEN TG_OP = 'DELETE' THEN OLD.institution_id ELSE NEW.institution_id END;
    UPDATE public.institutions SET updated_at = updated_at WHERE id = institution;
    IF TG_OP IN ('DELETE', 'UPDATE') AND OLD.role = 'owner'
       AND (TG_OP = 'DELETE' OR NEW.role <> 'owner')
       AND (SELECT count(*) FROM public.institution_members
            WHERE institution_id = institution AND role = 'owner') <= 1 THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Institution must retain an owner';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER institution_members_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.institution_members
FOR EACH ROW EXECUTE FUNCTION certichain_private.guard_institution_member();

-- Check the final transaction state, so an institution and its first owner can
-- be inserted atomically. This also prevents orphan creation by trusted SQL.
CREATE FUNCTION certichain_private.require_institution_owner()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    institution uuid;
BEGIN
    IF TG_TABLE_NAME = 'institutions' THEN
        institution := NEW.id;
    ELSIF TG_OP = 'DELETE' THEN
        institution := OLD.institution_id;
    ELSE
        institution := NEW.institution_id;
    END IF;
    IF EXISTS (SELECT 1 FROM public.institutions WHERE id = institution)
       AND NOT EXISTS (SELECT 1 FROM public.institution_members
                       WHERE institution_id = institution AND role = 'owner') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Institution must retain an owner';
    END IF;
    RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER institutions_require_owner
AFTER INSERT ON public.institutions DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION certichain_private.require_institution_owner();
CREATE CONSTRAINT TRIGGER institution_members_require_owner
AFTER INSERT OR UPDATE OR DELETE ON public.institution_members DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION certichain_private.require_institution_owner();

-- Internal helper: lock before checking database-backed authorization. The
-- caller cannot provide an actor ID, global role or verification status here.
CREATE FUNCTION certichain_private.lock_institution_for_management(p_institution uuid, p_details boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM 1 FROM public.institutions WHERE id = p_institution FOR UPDATE;
    IF NOT FOUND OR auth.uid() IS NULL OR NOT (
        certichain_private.is_platform_admin()
        OR certichain_private.has_institution_role(p_institution,
            CASE WHEN p_details THEN ARRAY['owner', 'admin']::public.institution_role[]
                 ELSE ARRAY['owner']::public.institution_role[] END)
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Institution administration is not permitted';
    END IF;
END;
$$;

CREATE FUNCTION public.create_institution(p_name text, p_slug text, p_owner uuid, p_website text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    institution uuid;
BEGIN
    IF auth.uid() IS NULL OR NOT certichain_private.is_platform_admin() THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Platform administration is required';
    END IF;
    PERFORM 1 FROM public.profiles AS p JOIN auth.users AS u ON u.id = p.id
        WHERE p.id = p_owner FOR KEY SHARE OF p, u;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Owner identity and profile must exist';
    END IF;
    INSERT INTO public.institutions (name, slug, website, verification_status)
    VALUES (p_name, p_slug, p_website, 'pending') RETURNING id INTO institution;
    INSERT INTO public.institution_members (institution_id, user_id, role)
    VALUES (institution, p_owner, 'owner');
    RETURN institution;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Institution slug is already in use';
    WHEN check_violation OR not_null_violation THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid institution details';
END;
$$;

CREATE FUNCTION public.update_institution_details(p_institution uuid, p_name text, p_slug text, p_website text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM certichain_private.lock_institution_for_management(p_institution, true);
    UPDATE public.institutions SET name = p_name, slug = p_slug, website = p_website,
        updated_at = now() WHERE id = p_institution;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'Institution slug is already in use';
    WHEN check_violation OR not_null_violation THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid institution details';
END;
$$;

CREATE FUNCTION public.set_institution_status(p_institution uuid, p_status public.institution_verification_status)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    previous_status public.institution_verification_status;
BEGIN
    IF auth.uid() IS NULL OR NOT certichain_private.is_platform_admin() THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Platform administration is required';
    END IF;
    SELECT verification_status INTO previous_status FROM public.institutions
        WHERE id = p_institution FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Institution does not exist';
    END IF;
    -- Retrying the same decision is safe. Re-review and reactivation are explicit.
    IF p_status IS NULL OR NOT (
        previous_status = p_status
        OR (previous_status = 'pending' AND p_status IN ('verified', 'rejected'))
        OR (previous_status = 'verified' AND p_status = 'suspended')
        OR (previous_status IN ('rejected', 'suspended') AND p_status = 'pending')
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid institution status transition';
    END IF;
    UPDATE public.institutions SET verification_status = p_status, updated_at = now()
        WHERE id = p_institution;
END;
$$;

CREATE FUNCTION public.set_institution_member(p_institution uuid, p_member uuid, p_role public.institution_role)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM certichain_private.lock_institution_for_management(p_institution, false);
    IF p_role IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Membership role is required';
    END IF;
    PERFORM 1 FROM public.profiles AS p JOIN auth.users AS u ON u.id = p.id
        WHERE p.id = p_member FOR KEY SHARE OF p, u;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Member identity and profile must exist';
    END IF;
    INSERT INTO public.institution_members (institution_id, user_id, role)
    VALUES (p_institution, p_member, p_role)
    ON CONFLICT (institution_id, user_id) DO UPDATE SET role = EXCLUDED.role;
END;
$$;

CREATE FUNCTION public.remove_institution_member(p_institution uuid, p_member uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM certichain_private.lock_institution_for_management(p_institution, false);
    DELETE FROM public.institution_members WHERE institution_id = p_institution AND user_id = p_member;
    -- Missing membership is an idempotent success for an authorized manager.
END;
$$;

REVOKE ALL ON FUNCTION certichain_private.prevent_institution_delete(),
    certichain_private.prevent_institution_truncate(),
    certichain_private.guard_institution_member(), certichain_private.require_institution_owner(),
    certichain_private.lock_institution_for_management(uuid, boolean),
    certichain_private.protect_profile_update(), certichain_private.protect_institution_update()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_institution(text, text, uuid, text),
    public.update_institution_details(uuid, text, text, text),
    public.set_institution_status(uuid, public.institution_verification_status),
    public.set_institution_member(uuid, uuid, public.institution_role),
    public.remove_institution_member(uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_institution(text, text, uuid, text),
    public.update_institution_details(uuid, text, text, text),
    public.set_institution_status(uuid, public.institution_verification_status),
    public.set_institution_member(uuid, uuid, public.institution_role),
    public.remove_institution_member(uuid, uuid)
    TO authenticated;
