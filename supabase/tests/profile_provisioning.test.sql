-- Run against local Supabase with `supabase test db --local`.
-- Exercise the real Auth table/trigger and RLS; all synthetic fixtures roll back.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET LOCAL search_path = public, extensions;
SELECT plan(39);

SELECT lives_ok($sql$
    INSERT INTO auth.users (id, raw_user_meta_data)
    VALUES ('00000000-0000-4000-8000-000000000001',
            '{"full_name":" \t Synthetic Holder \n "}'::jsonb)
$sql$, 'Administrative test session creates a user through the trusted trigger');
SELECT is((SELECT count(*) FROM public.profiles WHERE id = '00000000-0000-4000-8000-000000000001'),
          1::bigint, 'Exactly one profile uses the Auth user ID');
SELECT is((SELECT full_name FROM public.profiles WHERE id = '00000000-0000-4000-8000-000000000001'),
          'Synthetic Holder', 'Name is trimmed, including tabs and newlines');
SELECT is((SELECT role::text FROM public.profiles WHERE id = '00000000-0000-4000-8000-000000000001'),
          'holder', 'New profile starts as holder');

CREATE TEMP TABLE provisioning_counts AS
SELECT (SELECT count(*) FROM public.institutions) AS institutions,
       (SELECT count(*) FROM public.institution_members) AS members;
INSERT INTO auth.users (id, raw_user_meta_data) VALUES
    ('00000000-0000-4000-8000-000000000002',
     '{"full_name":"Synthetic Institution","role":"institution_admin","account_type":"Institución","institution_id":"00000000-0000-4000-8000-000000000099","institution_members":{"role":"owner"},"membership_role":"admin"}'),
    ('00000000-0000-4000-8000-000000000003',
     '{"full_name":"Synthetic Platform","role":"platform_admin","institution_role":"issuer"}');
SELECT is((SELECT role::text FROM public.profiles WHERE id = '00000000-0000-4000-8000-000000000002'),
          'holder', 'Metadata cannot assign institution_admin');
SELECT is((SELECT role::text FROM public.profiles WHERE id = '00000000-0000-4000-8000-000000000003'),
          'holder', 'Metadata cannot assign platform_admin');
SELECT is((SELECT count(*) FROM public.institutions),
          (SELECT institutions FROM provisioning_counts), 'Metadata creates no institution');
SELECT is((SELECT count(*) FROM public.institution_members),
          (SELECT members FROM provisioning_counts), 'Metadata creates no owner, admin or issuer membership');

-- Each throws_ok uses a subtransaction: failure must undo the Auth insert too.
SELECT throws_ok(
    pg_catalog.format('INSERT INTO auth.users (id, raw_user_meta_data) VALUES (%L, %L::jsonb)',
                      '00000000-0000-4000-8000-000000000010', metadata),
    '23514', 'Signup requires a nonblank full_name string', description
)
FROM (VALUES
    (NULL, 'SQL NULL metadata is rejected'),
    ('{}', 'Missing full_name is rejected'),
    ('null', 'Null metadata is rejected'),
    ('{"full_name":null}', 'Null full_name is rejected'),
    ('{"full_name":""}', 'Empty full_name is rejected'),
    ('{"full_name":"   "}', 'Space-only full_name is rejected'),
    ('{"full_name":"\t\n\r"}', 'Whitespace-only full_name is rejected'),
    ('{"full_name":123}', 'Numeric full_name is rejected'),
    ('{"full_name":{}}', 'Object full_name is rejected'),
    ('{"full_name":[]}', 'Array full_name is rejected'),
    ('{"full_name":true}', 'Boolean full_name is rejected')
) AS invalid_names(metadata, description);
SELECT is((SELECT count(*) FROM auth.users WHERE id = '00000000-0000-4000-8000-000000000010'),
          0::bigint, 'Failed provisioning leaves no Auth user');
SELECT is((SELECT count(*) FROM public.profiles WHERE id = '00000000-0000-4000-8000-000000000010'),
          0::bigint, 'Failed provisioning leaves no profile');

UPDATE auth.users SET raw_user_meta_data = '{"full_name":"Changed Metadata","role":"platform_admin"}'
WHERE id = '00000000-0000-4000-8000-000000000001';
SELECT is((SELECT full_name FROM public.profiles WHERE id = '00000000-0000-4000-8000-000000000001'),
          'Synthetic Holder', 'Metadata updates do not re-provision or overwrite the profile');

SELECT ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""']
           FROM pg_catalog.pg_proc
           WHERE oid = 'certichain_private.provision_auth_user_profile()'::regprocedure),
          'Provisioning is SECURITY DEFINER with an empty search_path');
SELECT ok(NOT pg_catalog.has_function_privilege('anon', 'certichain_private.provision_auth_user_profile()', 'EXECUTE')
          AND NOT pg_catalog.has_function_privilege('authenticated', 'certichain_private.provision_auth_user_profile()', 'EXECUTE')
          AND NOT pg_catalog.has_function_privilege('service_role', 'certichain_private.provision_auth_user_profile()', 'EXECUTE'),
          'API roles cannot execute provisioning directly');
SELECT is((SELECT count(*) FROM pg_catalog.pg_trigger
           WHERE tgrelid = 'auth.users'::regclass
             AND tgfoid = 'certichain_private.provision_auth_user_profile()'::regprocedure
             AND NOT tgisinternal AND tgtype = 5),
          1::bigint, 'Exactly one AFTER INSERT row trigger provisions profiles');
SELECT ok((SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid = 'public.profiles'::regclass),
          'Profile RLS remains enabled');
SELECT is((SELECT count(*) FROM pg_catalog.pg_policy
           WHERE polrelid = 'public.profiles'::regclass AND polcmd IN ('a', '*')),
          0::bigint, 'No profile INSERT or ALL policy was added');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*) FROM public.profiles), 1::bigint, 'Holder can read only their own profile');
SELECT lives_ok($sql$
    UPDATE public.profiles SET full_name = 'Synthetic Edited' WHERE id = auth.uid()
$sql$, 'Holder can still update their own name');
SELECT is((SELECT full_name FROM public.profiles WHERE id = auth.uid()),
          'Synthetic Edited', 'Own-name update persists');
WITH changed AS (
    UPDATE public.profiles SET full_name = 'Unauthorized Edit'
    WHERE id = '00000000-0000-4000-8000-000000000002' RETURNING id
)
SELECT is((SELECT count(*) FROM changed), 0::bigint, 'Holder cannot update another profile');
SELECT throws_ok($sql$
    UPDATE public.profiles SET role = 'platform_admin' WHERE id = auth.uid()
$sql$, 'P0001', 'Only a platform administrator may change a global role', 'Role-change protection remains active');
SELECT throws_ok($sql$
    UPDATE public.profiles SET full_name = E' \t\n ' WHERE id = auth.uid()
$sql$, '23514', NULL, 'Constraint rejects whitespace on profile updates');
SELECT throws_ok($sql$
    INSERT INTO public.profiles (id, full_name)
    VALUES ('00000000-0000-4000-8000-000000000020', 'Synthetic Arbitrary')
$sql$, '42501', NULL, 'Authenticated client cannot insert an arbitrary profile');
RESET ROLE;

SET LOCAL ROLE anon;
SELECT is((SELECT count(*) FROM public.profiles), 0::bigint, 'Anonymous client cannot read profiles');
SELECT throws_ok($sql$
    INSERT INTO public.profiles (id, full_name)
    VALUES ('00000000-0000-4000-8000-000000000021', 'Synthetic Anonymous')
$sql$, '42501', NULL, 'Anonymous client cannot insert profiles');
RESET ROLE;

-- Trusted test-only admin fixture; no production admin-provisioning mechanism.
DELETE FROM public.profiles WHERE id = '00000000-0000-4000-8000-000000000003';
INSERT INTO public.profiles (id, full_name, role)
VALUES ('00000000-0000-4000-8000-000000000003', 'Synthetic Admin Fixture', 'platform_admin');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*) FROM public.profiles WHERE id IN (
    '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000003')), 3::bigint, 'Platform admin still reads other profiles');
SELECT lives_ok($sql$
    UPDATE public.profiles SET full_name = 'Synthetic Admin Edit'
    WHERE id = '00000000-0000-4000-8000-000000000002'
$sql$, 'Platform admin still updates other profiles');
SELECT is((SELECT full_name FROM public.profiles WHERE id = '00000000-0000-4000-8000-000000000002'),
          'Synthetic Admin Edit', 'Admin update persists');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
