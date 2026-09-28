-- Local integration tests: real API roles, database-backed memberships and JWT
-- claims. Only fixture setup uses postgres; all client statements are invoker SQL.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET LOCAL search_path = public, extensions;
SELECT no_plan();

-- Synthetic fixtures begin.
INSERT INTO auth.users (id, raw_user_meta_data)
SELECT ('50000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       jsonb_build_object('full_name', 'Synthetic Phase 5 User ' || n)
FROM generate_series(1, 8) AS n;

-- Trusted, test-only global roles; no production provisioning or credentials.
DELETE FROM public.profiles WHERE id IN (
    '50000000-0000-4000-8000-000000000006',
    '50000000-0000-4000-8000-000000000008'
);
INSERT INTO public.profiles (id, full_name, role) VALUES
    ('50000000-0000-4000-8000-000000000006', 'Synthetic Platform Admin', 'platform_admin'),
    ('50000000-0000-4000-8000-000000000008', 'Synthetic Unaffiliated Admin', 'institution_admin');

INSERT INTO public.institutions (id, name, slug, verification_status) VALUES
    ('50000000-0000-4000-8000-000000000101', 'Synthetic Pending', 'phase5-pending', 'pending'),
    ('50000000-0000-4000-8000-000000000102', 'Synthetic Verified', 'phase5-verified', 'verified'),
    ('50000000-0000-4000-8000-000000000103', 'Synthetic Suspended', 'phase5-suspended', 'suspended'),
    ('50000000-0000-4000-8000-000000000104', 'Synthetic Rejected', 'phase5-rejected', 'rejected'),
    ('50000000-0000-4000-8000-000000000105', 'Synthetic Other', 'phase5-other', 'verified');

INSERT INTO public.institution_members (institution_id, user_id, role)
SELECT i.id, r.user_id, r.role::public.institution_role
FROM public.institutions AS i
CROSS JOIN (VALUES
    ('50000000-0000-4000-8000-000000000003'::uuid, 'issuer'),
    ('50000000-0000-4000-8000-000000000004'::uuid, 'admin'),
    ('50000000-0000-4000-8000-000000000005'::uuid, 'owner')
) AS r(user_id, role)
WHERE i.slug IN ('phase5-pending', 'phase5-verified', 'phase5-suspended', 'phase5-rejected');
INSERT INTO public.institution_members (institution_id, user_id, role) VALUES
    ('50000000-0000-4000-8000-000000000105', '50000000-0000-4000-8000-000000000007', 'owner');

INSERT INTO public.certificates (
    id, holder_id, institution_id, issued_by, title, credential_code,
    description, document_path, document_hash, issued_at, expires_at
)
SELECT ('50000000-0000-4000-8000-' || lpad((200 + n)::text, 12, '0'))::uuid,
       '50000000-0000-4000-8000-000000000001'::uuid,
       ('50000000-0000-4000-8000-' || lpad((100 + n)::text, 12, '0'))::uuid,
       '50000000-0000-4000-8000-000000000003'::uuid,
       'Synthetic Certificate ' || n, 'phase5-certificate-' || n,
       'Synthetic immutable metadata', 'synthetic/' || n || '.pdf', repeat('a', 64),
       '2026-01-01T00:00:00Z'::timestamptz, '2027-01-01T00:00:00Z'::timestamptz
FROM generate_series(1, 4) AS n;
INSERT INTO public.certificates (id, holder_id, institution_id, issued_by, title, credential_code) VALUES
    ('50000000-0000-4000-8000-000000000205', '50000000-0000-4000-8000-000000000002',
     '50000000-0000-4000-8000-000000000102', '50000000-0000-4000-8000-000000000003',
     'Synthetic Other Holder', 'phase5-other-holder'),
    ('50000000-0000-4000-8000-000000000206', '50000000-0000-4000-8000-000000000002',
     '50000000-0000-4000-8000-000000000105', '50000000-0000-4000-8000-000000000007',
     'Synthetic Other Institution', 'phase5-other-institution');

CREATE TEMP TABLE phase5_snapshot AS
SELECT 'profiles' AS table_name, jsonb_agg(to_jsonb(p) ORDER BY id) AS rows FROM public.profiles AS p
UNION ALL
SELECT 'institutions', jsonb_agg(to_jsonb(i) ORDER BY id) FROM public.institutions AS i
UNION ALL
SELECT 'institution_members', jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.institution_members AS m
UNION ALL
SELECT 'certificates', jsonb_agg(to_jsonb(c) ORDER BY id) FROM public.certificates AS c;
-- Synthetic fixtures end.

SELECT ok((SELECT bool_and(relrowsecurity) FROM pg_class WHERE oid IN (
    'public.profiles'::regclass, 'public.institutions'::regclass,
    'public.institution_members'::regclass, 'public.certificates'::regclass
)), 'RLS remains enabled on every private table');
SELECT is((SELECT count(*) FROM pg_policy WHERE polrelid = 'public.certificates'::regclass AND polcmd <> 'r'),
          0::bigint, 'Certificates have no INSERT, UPDATE, DELETE or ALL policy');
SELECT ok(has_table_privilege('authenticated', 'public.certificates', 'SELECT'), 'Authenticated retains SELECT');
SELECT ok(NOT has_table_privilege(r, 'public.certificates', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
          AND NOT has_any_column_privilege(r, 'public.certificates', 'INSERT,UPDATE,REFERENCES'),
          r || ' has no certificate write grants, including column grants')
FROM (VALUES ('anon'), ('authenticated')) AS roles(r);
SELECT ok(NOT has_table_privilege('anon', 'public.certificates', 'SELECT'), 'Anon has no certificate SELECT grant');
SELECT ok(NOT has_function_privilege('authenticated', 'certichain_private.protect_certificate_update()', 'EXECUTE'),
          'Legacy certificate trigger is not a client operation');

CREATE FUNCTION pg_temp.check_certificate_client(
    p_user uuid, p_institution uuid, p_certificate uuid, p_visible uuid[], p_label text
)
RETURNS SETOF text
LANGUAGE plpgsql SECURITY INVOKER
AS $$
BEGIN
    PERFORM set_config('request.jwt.claim.sub', p_user::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', p_user, 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    RETURN NEXT is(current_user::text, 'authenticated', p_label || ': API database role is authenticated');
    RETURN NEXT is(auth.uid(), p_user, p_label || ': JWT subject is the expected caller');
    RETURN NEXT is((SELECT coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[]) FROM public.certificates),
                   p_visible, p_label || ': exact authorized certificate reads');
    RETURN NEXT throws_ok(format(
        'INSERT INTO public.certificates (holder_id, institution_id, issued_by, title, credential_code)
         VALUES (%L, %L, %L, %L, %L)',
        '50000000-0000-4000-8000-000000000001', p_institution, p_user,
        'Synthetic Denied', 'phase5-denied'),
        '42501', 'permission denied for table certificates', p_label || ': direct issuance is denied');
    RETURN NEXT throws_ok(format(
        'UPDATE public.certificates SET status = ''revoked'', revoked_at = now() WHERE id = %L', p_certificate),
        '42501', 'permission denied for table certificates', p_label || ': direct revocation is denied');
    RETURN NEXT throws_ok(format(
        'UPDATE public.certificates SET title = ''Synthetic Tampered'' WHERE id = %L', p_certificate),
        '42501', 'permission denied for table certificates', p_label || ': metadata update is denied');
    RETURN NEXT throws_ok(format(
        'INSERT INTO public.certificates (id, holder_id, institution_id, issued_by, title, credential_code)
         VALUES (%L, %L, %L, %L, %L, %L) ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title',
        p_certificate, '50000000-0000-4000-8000-000000000001', p_institution, p_user,
        'Synthetic Upsert', 'phase5-denied'),
        '42501', 'permission denied for table certificates', p_label || ': upsert is denied');
    RETURN NEXT throws_ok(format('DELETE FROM public.certificates WHERE id = %L', p_certificate),
        '42501', 'permission denied for table certificates', p_label || ': deletion is denied');
    RETURN NEXT throws_ok('TRUNCATE public.certificates',
        '42501', 'permission denied for table certificates', p_label || ': truncate is denied');
    RESET ROLE;
    RETURN NEXT is((SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM public.certificates AS c),
                   (SELECT rows FROM phase5_snapshot WHERE table_name = 'certificates'),
                   p_label || ': every certificate remains intact after rejected writes');
END;
$$;

-- For every member, reads include all their institutions, independently of
-- verification status. Writes target each status separately and must all fail.
SELECT tests.* FROM (VALUES
    ('50000000-0000-4000-8000-000000000003'::uuid, 'issuer'),
    ('50000000-0000-4000-8000-000000000004'::uuid, 'admin'),
    ('50000000-0000-4000-8000-000000000005'::uuid, 'owner')
) AS r(user_id, role)
CROSS JOIN public.institutions AS i
JOIN public.certificates AS c ON c.institution_id = i.id
CROSS JOIN LATERAL pg_temp.check_certificate_client(
    r.user_id, i.id, c.id,
    ARRAY['50000000-0000-4000-8000-000000000201', '50000000-0000-4000-8000-000000000202',
          '50000000-0000-4000-8000-000000000203', '50000000-0000-4000-8000-000000000204',
          '50000000-0000-4000-8000-000000000205']::uuid[],
    r.role || ' / ' || i.verification_status
) AS tests
WHERE i.slug IN ('phase5-pending', 'phase5-verified', 'phase5-suspended', 'phase5-rejected')
  AND c.holder_id = '50000000-0000-4000-8000-000000000001';

SELECT * FROM pg_temp.check_certificate_client(
    '50000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000102',
    '50000000-0000-4000-8000-000000000202',
    ARRAY['50000000-0000-4000-8000-000000000201', '50000000-0000-4000-8000-000000000202',
          '50000000-0000-4000-8000-000000000203', '50000000-0000-4000-8000-000000000204']::uuid[], 'Holder A');
SELECT * FROM pg_temp.check_certificate_client(
    '50000000-0000-4000-8000-000000000002', '50000000-0000-4000-8000-000000000102',
    '50000000-0000-4000-8000-000000000205',
    ARRAY['50000000-0000-4000-8000-000000000205', '50000000-0000-4000-8000-000000000206']::uuid[], 'Holder B');
SELECT * FROM pg_temp.check_certificate_client(
    '50000000-0000-4000-8000-000000000006', '50000000-0000-4000-8000-000000000102',
    '50000000-0000-4000-8000-000000000202',
    ARRAY['50000000-0000-4000-8000-000000000201', '50000000-0000-4000-8000-000000000202',
          '50000000-0000-4000-8000-000000000203', '50000000-0000-4000-8000-000000000204',
          '50000000-0000-4000-8000-000000000205', '50000000-0000-4000-8000-000000000206']::uuid[], 'Platform admin');
SELECT * FROM pg_temp.check_certificate_client(
    '50000000-0000-4000-8000-000000000007', '50000000-0000-4000-8000-000000000102',
    '50000000-0000-4000-8000-000000000202',
    ARRAY['50000000-0000-4000-8000-000000000206']::uuid[], 'Owner of another institution');
SELECT * FROM pg_temp.check_certificate_client(
    '50000000-0000-4000-8000-000000000008', '50000000-0000-4000-8000-000000000102',
    '50000000-0000-4000-8000-000000000202', ARRAY[]::uuid[], 'Unaffiliated institution_admin');

SELECT set_config('request.jwt.claim.sub', '50000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"50000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
-- Match Flutter 4D's minimal wallet/detail selection and optional issuer join.
SELECT is((SELECT count(*) FROM public.certificates AS c LEFT JOIN public.institutions AS i ON i.id = c.institution_id
           WHERE c.holder_id = auth.uid() AND i.name IS NULL), 4::bigint,
          'Holder wallet preserves certificates when issuer name is hidden by RLS');
SELECT results_eq($sql$
    SELECT c.id, c.holder_id, c.institution_id, c.title, c.issued_at, c.expires_at, c.status::text, i.name
    FROM public.certificates AS c LEFT JOIN public.institutions AS i ON i.id = c.institution_id
    WHERE c.id = '50000000-0000-4000-8000-000000000202' AND c.holder_id = auth.uid()
$sql$, $sql$
    VALUES ('50000000-0000-4000-8000-000000000202'::uuid, '50000000-0000-4000-8000-000000000001'::uuid,
            '50000000-0000-4000-8000-000000000102'::uuid, 'Synthetic Certificate 2'::text,
            '2026-01-01T00:00:00Z'::timestamptz, '2027-01-01T00:00:00Z'::timestamptz, 'active'::text, NULL::text)
$sql$, 'Flutter detail still reads its own minimal fields');
SELECT is((SELECT count(*) FROM public.certificates WHERE id = '50000000-0000-4000-8000-000000000205'),
          0::bigint, 'Holder cannot read another holder detail even without a holder filter');
RESET ROLE;

-- RLS supplies a second barrier if a future change mistakenly regrants DML.
-- These grants exist only in this rollback-only test transaction.
GRANT INSERT, UPDATE ON public.certificates TO authenticated;
SELECT set_config('request.jwt.claim.sub', '50000000-0000-4000-8000-000000000006', true);
SELECT set_config('request.jwt.claims', '{"sub":"50000000-0000-4000-8000-000000000006","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
SELECT throws_ok($sql$
    INSERT INTO public.certificates (holder_id, institution_id, issued_by, title, credential_code)
    VALUES ('50000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000102',
            auth.uid(), 'Synthetic RLS Denied', 'phase5-rls-denied')
$sql$, '42501', 'new row violates row-level security policy for table "certificates"',
          'Even with a DML grant, RLS denies platform_admin issuance');
WITH changed AS (
    UPDATE public.certificates SET status = 'revoked', revoked_at = now() RETURNING id
)
SELECT is((SELECT count(*) FROM changed), 0::bigint, 'Even with a DML grant, RLS hides all rows from UPDATE');
RESET ROLE;
REVOKE INSERT, UPDATE ON public.certificates FROM authenticated;

SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SET LOCAL ROLE anon;
SELECT is(current_user::text, 'anon', 'Anonymous tests run as the anon API role');
SELECT ok(auth.uid() IS NULL, 'Anonymous request has no subject');
SELECT throws_ok('SELECT * FROM public.certificates', '42501', 'permission denied for table certificates',
                 'Anon has no direct certificate reads');
SELECT is((SELECT count(*) FROM public.profiles), 0::bigint, 'Anon has no profile rows');
SELECT is((SELECT count(*) FROM public.institutions), 0::bigint, 'Anon has no institution rows');
SELECT is((SELECT count(*) FROM public.institution_members), 0::bigint, 'Anon has no membership rows');
SELECT throws_ok($sql$
    INSERT INTO public.certificates (holder_id, institution_id, issued_by, title, credential_code)
    VALUES ('50000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000102',
            '50000000-0000-4000-8000-000000000003', 'Synthetic Anon Denied', 'phase5-anon-denied')
$sql$, '42501', 'permission denied for table certificates', 'Anon cannot issue');
SELECT throws_ok('UPDATE public.certificates SET status = ''revoked'', revoked_at = now()',
                 '42501', 'permission denied for table certificates', 'Anon cannot revoke');
SELECT throws_ok('TRUNCATE public.' || t || ' CASCADE', '42501', 'permission denied for table ' || t,
                 'Anon cannot truncate ' || t)
FROM (VALUES ('certificates'), ('profiles'), ('institutions'), ('institution_members')) AS tables(t);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '50000000-0000-4000-8000-000000000006', true);
SELECT set_config('request.jwt.claims', '{"sub":"50000000-0000-4000-8000-000000000006","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
SELECT throws_ok('TRUNCATE public.' || t || ' CASCADE', '42501', 'permission denied for table ' || t,
                 'Platform admin cannot truncate ' || t)
FROM (VALUES ('profiles'), ('institutions'), ('institution_members')) AS tables(t);
SELECT is((SELECT count(*) FROM public.institutions), 5::bigint, 'Platform admin still reads institutions');
SELECT is((SELECT count(*) FROM public.institution_members), 13::bigint, 'Platform admin still reads memberships');
RESET ROLE;

SELECT is((SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM public.certificates AS c),
          (SELECT rows FROM phase5_snapshot WHERE table_name = 'certificates'),
          'All existing certificate fields remain unchanged after every rejected operation');
SELECT is((SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM public.profiles AS p),
          (SELECT rows FROM phase5_snapshot WHERE table_name = 'profiles'), 'Profiles remain intact');
SELECT is((SELECT jsonb_agg(to_jsonb(i) ORDER BY id) FROM public.institutions AS i),
          (SELECT rows FROM phase5_snapshot WHERE table_name = 'institutions'), 'Institutions remain intact');
SELECT is((SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.institution_members AS m),
          (SELECT rows FROM phase5_snapshot WHERE table_name = 'institution_members'), 'Memberships remain intact');
SELECT * FROM finish();
ROLLBACK;
