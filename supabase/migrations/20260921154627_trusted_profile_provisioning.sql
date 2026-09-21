-- Fail before adding the constraint if existing data needs explicit remediation.
-- Never repair a person's name with a fabricated value or log the invalid data.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.profiles
        WHERE pg_catalog.regexp_replace(full_name, '^[[:space:]]+|[[:space:]]+$', '', 'g') = ''
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'Existing profiles contain blank full_name values; review and correct them explicitly before retrying this migration';
    END IF;
END;
$$;

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_full_name_not_blank CHECK (
        pg_catalog.regexp_replace(full_name, '^[[:space:]]+|[[:space:]]+$', '', 'g') <> ''
    );

-- Owned by the trusted migration/table owner, following the existing private
-- SECURITY DEFINER functions. No client receives EXECUTE or new table grants.
CREATE FUNCTION certichain_private.provision_auth_user_profile()
RETURNS pg_catalog.trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    profile_full_name pg_catalog.text;
BEGIN
    IF pg_catalog.jsonb_typeof(NEW.raw_user_meta_data -> 'full_name') IS DISTINCT FROM 'string' THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514', MESSAGE = 'Signup requires a nonblank full_name string';
    END IF;

    profile_full_name := pg_catalog.regexp_replace(
        NEW.raw_user_meta_data ->> 'full_name', '^[[:space:]]+|[[:space:]]+$', '', 'g'
    );
    IF profile_full_name = '' THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514', MESSAGE = 'Signup requires a nonblank full_name string';
    END IF;

    INSERT INTO public.profiles (id, full_name, role)
    VALUES (NEW.id, profile_full_name, 'holder'::public.user_role);

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION certichain_private.provision_auth_user_profile()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER certichain_auth_user_provision_profile
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION certichain_private.provision_auth_user_profile();
