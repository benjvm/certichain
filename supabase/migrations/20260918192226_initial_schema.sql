-- Supabase Auth owns identities; application data is stored in public.
CREATE TYPE public.user_role AS ENUM ('holder', 'institution_admin', 'platform_admin');
CREATE TYPE public.institution_role AS ENUM ('owner', 'admin', 'issuer');
CREATE TYPE public.institution_verification_status AS ENUM ('pending', 'verified', 'rejected', 'suspended');
CREATE TYPE public.certificate_status AS ENUM ('active', 'revoked');

CREATE TABLE public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    full_name text NOT NULL,
    role public.user_role NOT NULL DEFAULT 'holder',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.institutions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    slug text NOT NULL UNIQUE,
    website text,
    verification_status public.institution_verification_status NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT institutions_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT institutions_slug_not_blank CHECK (btrim(slug) <> '')
);

CREATE TABLE public.institution_members (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES public.institutions (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
    role public.institution_role NOT NULL DEFAULT 'issuer',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT institution_members_institution_user_unique UNIQUE (institution_id, user_id)
);

CREATE TABLE public.certificates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    holder_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
    institution_id uuid NOT NULL REFERENCES public.institutions (id) ON DELETE RESTRICT,
    issued_by uuid NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
    title text NOT NULL,
    description text,
    credential_code text NOT NULL UNIQUE,
    document_path text,
    document_hash text,
    status public.certificate_status NOT NULL DEFAULT 'active',
    issued_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT certificates_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT certificates_credential_code_not_blank CHECK (btrim(credential_code) <> ''),
    CONSTRAINT certificates_expiration_after_issuance CHECK (expires_at IS NULL OR expires_at >= issued_at),
    CONSTRAINT certificates_revocation_consistent CHECK (
        (status = 'active' AND revoked_at IS NULL)
        OR (status = 'revoked' AND revoked_at IS NOT NULL)
    )
);

CREATE INDEX certificates_holder_id_idx ON public.certificates (holder_id);
CREATE INDEX certificates_institution_id_idx ON public.certificates (institution_id);
CREATE INDEX certificates_issued_by_idx ON public.certificates (issued_by);
CREATE INDEX institution_members_user_id_idx ON public.institution_members (user_id);
-- The unique (institution_id, user_id) index also serves institution_id lookups.

-- Deny API role access until a separate migration defines least-privilege policies.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.institutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.institution_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.certificates ENABLE ROW LEVEL SECURITY;
