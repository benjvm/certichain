-- Phase 6 integration tests. Only setup/bootstrap uses postgres.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET LOCAL search_path = public, extensions;
SELECT no_plan();

INSERT INTO auth.users (id, raw_user_meta_data)
SELECT ('60000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       jsonb_build_object('full_name', 'Synthetic Phase 6 User ' || n, 'role', 'platform_admin')
FROM generate_series(1, 10) AS n;
UPDATE public.profiles SET role = 'institution_admin'
WHERE id = '60000000-0000-4000-8000-000000000006';

SELECT is((SELECT count(*) FROM public.profiles WHERE role = 'platform_admin'), 0::bigint,
          'Auth metadata never bootstraps an admin');
SELECT ok(NOT has_function_privilege(r, 'certichain_private.grant_platform_admin(uuid,uuid,integer)', 'EXECUTE'),
          r || ' cannot execute trusted bootstrap')
FROM (VALUES ('anon'), ('authenticated'), ('service_role')) AS roles(r);
SELECT ok((SELECT NOT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc
           WHERE oid = 'certichain_private.grant_platform_admin(uuid,uuid,integer)'::regprocedure),
          'Bootstrap is invoker SQL with a fixed search path');
SELECT throws_ok($sql$ SELECT certichain_private.grant_platform_admin(
    '60000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000002', 0)
$sql$, '22023', 'Confirm the target identity and expected administrator count', 'Bootstrap requires matching confirmation');
SELECT throws_ok($sql$ SELECT certichain_private.grant_platform_admin(NULL,NULL,0)
$sql$, '22023', NULL, 'Bootstrap rejects null target');
SELECT throws_ok($sql$ SELECT certichain_private.grant_platform_admin(
    '60000000-0000-4000-8000-000000000099', '60000000-0000-4000-8000-000000000099', 0)
$sql$, '22023', 'Target Auth identity and profile must exist', 'Bootstrap rejects nonexistent identity');
DELETE FROM public.profiles WHERE id = '60000000-0000-4000-8000-000000000010';
SELECT throws_ok($sql$ SELECT certichain_private.grant_platform_admin(
    '60000000-0000-4000-8000-000000000010', '60000000-0000-4000-8000-000000000010', 0)
$sql$, '22023', 'Target Auth identity and profile must exist', 'Bootstrap rejects missing profile');
SELECT is(certichain_private.grant_platform_admin(
    '60000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000001', 0),
    'platform_admin_assigned', 'Trusted SQL grants first admin explicitly');
SELECT is((SELECT count(*) FROM public.profiles WHERE role = 'platform_admin'), 1::bigint,
          'Exactly the intended profile is promoted');
SELECT is((SELECT role::text FROM public.profiles WHERE id = '60000000-0000-4000-8000-000000000002'),
          'holder', 'Another identity remains holder');
SELECT throws_ok($sql$ SELECT certichain_private.grant_platform_admin(
    '60000000-0000-4000-8000-000000000008', '60000000-0000-4000-8000-000000000008', 0)
$sql$, '23514', 'Administrator count changed; review before retrying', 'Initial bootstrap cannot run again blindly');
SELECT is(certichain_private.grant_platform_admin(
    '60000000-0000-4000-8000-000000000008', '60000000-0000-4000-8000-000000000008', 1),
    'platform_admin_assigned', 'Additional admin also requires trusted SQL and current count');
SELECT is(certichain_private.grant_platform_admin(
    '60000000-0000-4000-8000-000000000008', '60000000-0000-4000-8000-000000000008', 2),
    'already_platform_admin', 'Confirmed retry reports already assigned');

CREATE FUNCTION pg_temp.phase6_actor(p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
    PERFORM set_config('request.jwt.claim.sub', p_user::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', p_user, 'role', 'authenticated',
        'user_metadata', jsonb_build_object('role', 'platform_admin'))::text, true);
END;
$$;

SELECT pg_temp.phase6_actor('60000000-0000-4000-8000-000000000002');
SET LOCAL ROLE authenticated;
SELECT is(current_user::text, 'authenticated', 'Normal-user checks use effective API role');
SELECT is(auth.uid(), '60000000-0000-4000-8000-000000000002'::uuid, 'Normal-user subject comes from claims');
SELECT throws_ok($sql$ UPDATE public.profiles SET role = 'platform_admin' WHERE id = auth.uid()
$sql$, 'P0001', 'Global roles require trusted administrative SQL', 'Ordinary profile update cannot promote self');
SELECT throws_ok($sql$ SELECT certichain_private.grant_platform_admin(auth.uid(),auth.uid(),2)
$sql$, '42501', NULL, 'Authenticated cannot invoke bootstrap');
SELECT throws_ok($sql$ SELECT public.create_institution('Synthetic Denied','phase6-denied',auth.uid())
$sql$, '42501', 'Platform administration is required', 'Holder cannot create institution despite forged metadata');
SELECT throws_ok($sql$ INSERT INTO public.institutions(name,slug) VALUES ('Synthetic Denied','phase6-direct')
$sql$, '42501', NULL, 'Holder cannot create directly');
RESET ROLE;

SELECT pg_temp.phase6_actor('60000000-0000-4000-8000-000000000001');
SET LOCAL ROLE authenticated;
SELECT throws_ok($sql$ UPDATE public.profiles SET role = 'platform_admin'
    WHERE id = '60000000-0000-4000-8000-000000000002'
$sql$, 'P0001', 'Global roles require trusted administrative SQL', 'Even API platform admin cannot grant global roles');
SELECT throws_ok($sql$ SELECT public.create_institution('Synthetic Invalid Owner','phase6-invalid-owner',
    '60000000-0000-4000-8000-000000000099')
$sql$, '22023', 'Owner identity and profile must exist', 'Missing owner prevents creation');
SELECT throws_ok($sql$ SELECT public.create_institution('Synthetic Missing Profile','phase6-missing-profile',
    '60000000-0000-4000-8000-000000000010')
$sql$, '22023', 'Owner identity and profile must exist', 'Auth alone is insufficient for owner');
SELECT throws_ok(format('SELECT public.create_institution(%L,%L,%L,%L)', name, slug,
    '60000000-0000-4000-8000-000000000002', website), '22023', 'Invalid institution details', label)
FROM (VALUES
    (' ', 'phase6-invalid', NULL, 'Blank name rejected'),
    ('X', 'phase6-invalid', NULL, 'Short name rejected'),
    (repeat('x',161), 'phase6-invalid', NULL, 'Long name rejected'),
    (E'Synthetic\nName', 'phase6-invalid', NULL, 'Control characters rejected'),
    (' Synthetic', 'phase6-invalid', NULL, 'Untrimmed name rejected'),
    ('Synthetic', 'Uppercase', NULL, 'Noncanonical slug rejected'),
    ('Synthetic', 'institución', NULL, 'Non-ASCII slug rejected'),
    ('Synthetic', 'ab', NULL, 'Short slug rejected'),
    ('Synthetic', repeat('a',81), NULL, 'Long slug rejected'),
    ('Synthetic', 'double--dash', NULL, 'Double dash rejected'),
    ('Synthetic', 'phase6-invalid', 'http://example.invalid', 'Non-HTTPS website rejected'),
    (NULL, 'phase6-invalid', NULL, 'Null name rejected'),
    ('Synthetic', NULL, NULL, 'Null slug rejected')
) AS invalid(name,slug,website,label);
SELECT set_config('test.phase6_institution', public.create_institution(
    'Synthetic Main','phase6-main','60000000-0000-4000-8000-000000000002')::text, true);
SELECT is((SELECT verification_status::text FROM public.institutions WHERE slug='phase6-main'),
          'pending', 'Managed creation always starts pending');
SELECT is((SELECT user_id FROM public.institution_members
           WHERE institution_id=current_setting('test.phase6_institution')::uuid AND role='owner'),
          '60000000-0000-4000-8000-000000000002'::uuid, 'First owner is created in same operation');
SELECT is((SELECT role::text FROM public.profiles WHERE id='60000000-0000-4000-8000-000000000002'),
          'holder', 'Membership does not change global holder role');
SELECT throws_ok($sql$ SELECT public.create_institution('Synthetic Duplicate','phase6-main',
    '60000000-0000-4000-8000-000000000003')
$sql$, '23505', 'Institution slug is already in use', 'Duplicate slug has a fixed safe error');
SELECT is((SELECT count(*) FROM public.institutions WHERE slug='phase6-main'),1::bigint,'Duplicate creates no second institution');
SELECT lives_ok($sql$ SELECT public.create_institution('Synthetic Main','phase6-same-name',
    '60000000-0000-4000-8000-000000000003')
$sql$, 'Names may repeat if slug differs');
SELECT throws_ok($sql$ INSERT INTO public.institutions(name,slug) VALUES ('Synthetic Direct','phase6-direct')
$sql$, '42501', NULL, 'API platform admin cannot bypass atomic creation');
RESET ROLE;

-- Force failure at the second step, after the institution INSERT executed.
CREATE FUNCTION pg_temp.phase6_fail_owner() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Synthetic owner failure'; END;
$$;
CREATE TRIGGER phase6_fail_owner BEFORE INSERT ON public.institution_members
FOR EACH ROW EXECUTE FUNCTION pg_temp.phase6_fail_owner();
SET LOCAL ROLE authenticated;
SELECT throws_ok($sql$ SELECT public.create_institution('Synthetic Atomic','phase6-atomic',
    '60000000-0000-4000-8000-000000000003')
$sql$, '22023', 'Invalid institution details', 'Failure of owner INSERT aborts creation');
RESET ROLE;
DROP TRIGGER phase6_fail_owner ON public.institution_members;
SELECT is((SELECT count(*) FROM public.institutions WHERE slug IN
    ('phase6-atomic','phase6-invalid-owner','phase6-missing-profile','phase6-invalid')),0::bigint,
    'All failed creations leave no institution');
SELECT throws_ok($sql$
    DO $body$ BEGIN
        INSERT INTO public.institutions(name,slug) VALUES ('Synthetic Orphan','phase6-orphan');
        SET CONSTRAINTS institutions_require_owner IMMEDIATE;
    END $body$;
$sql$, '23514', 'Institution must retain an owner', 'Trusted orphan insert fails deferred invariant');
SELECT is((SELECT count(*) FROM public.institutions WHERE slug='phase6-orphan'),0::bigint,'Orphan transaction rolled back');

-- Owner/member authorization, including each state and cross-institution access.
SELECT pg_temp.phase6_actor('60000000-0000-4000-8000-000000000002');
SET LOCAL ROLE authenticated;
SELECT throws_ok($sql$ SELECT public.set_institution_status(current_setting('test.phase6_institution')::uuid,'verified')
$sql$, '42501', 'Platform administration is required', 'Owner cannot self-approve');
SELECT throws_ok($sql$ UPDATE public.institutions SET verification_status='verified'
    WHERE id=current_setting('test.phase6_institution')::uuid
$sql$, '42501', NULL, 'Owner cannot approve by direct UPDATE');
SELECT lives_ok($sql$ SELECT public.update_institution_details(current_setting('test.phase6_institution')::uuid,
    'Synthetic Owner Edit','phase6-main','https://example.invalid')
$sql$, 'Owner may edit allowed details');
SELECT throws_ok($sql$ SELECT public.set_institution_member(current_setting('test.phase6_institution')::uuid,auth.uid(),'admin')
$sql$, '23514', 'Institution must retain an owner', 'Last owner cannot demote self');
SELECT throws_ok($sql$ SELECT public.remove_institution_member(current_setting('test.phase6_institution')::uuid,auth.uid())
$sql$, '23514', 'Institution must retain an owner', 'Last owner cannot remove self');
SELECT lives_ok($sql$ SELECT public.set_institution_member(current_setting('test.phase6_institution')::uuid,
    '60000000-0000-4000-8000-000000000004','admin')
$sql$, 'Owner may add an institutional admin');
SELECT lives_ok($sql$ SELECT public.set_institution_member(current_setting('test.phase6_institution')::uuid,
    '60000000-0000-4000-8000-000000000005','issuer')
$sql$, 'Owner may add issuer');
SELECT throws_ok($sql$ SELECT public.set_institution_member(current_setting('test.phase6_institution')::uuid,
    '60000000-0000-4000-8000-000000000099','issuer')
$sql$, '22023', 'Member identity and profile must exist', 'Missing member gives safe error');
SELECT throws_ok($sql$ SELECT public.set_institution_member(current_setting('test.phase6_institution')::uuid,auth.uid(),NULL)
$sql$, '22023', NULL, 'Null role rejected');
SELECT throws_ok($sql$ INSERT INTO public.institution_members(institution_id,user_id,role)
    VALUES(current_setting('test.phase6_institution')::uuid,'60000000-0000-4000-8000-000000000007','owner')
$sql$, '42501', NULL, 'Owner cannot bypass membership operation');
RESET ROLE;

CREATE FUNCTION pg_temp.phase6_denied_manager(p_actor uuid, p_label text)
RETURNS SETOF text LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
    PERFORM pg_temp.phase6_actor(p_actor);
    SET LOCAL ROLE authenticated;
    RETURN NEXT is(current_user::text,'authenticated',p_label || ': effective API role');
    RETURN NEXT is(auth.uid(),p_actor,p_label || ': expected subject');
    RETURN NEXT throws_ok('SELECT public.set_institution_status(current_setting(''test.phase6_institution'')::uuid,''suspended'')',
        '42501','Platform administration is required',p_label || ': cannot change status');
    RETURN NEXT throws_ok('SELECT public.create_institution(''Synthetic Denied'',''phase6-denied'',auth.uid())',
        '42501','Platform administration is required',p_label || ': cannot create');
    RETURN NEXT throws_ok('SELECT public.set_institution_member(current_setting(''test.phase6_institution'')::uuid,
        ''60000000-0000-4000-8000-000000000007'',''owner'')',
        '42501','Institution administration is not permitted',p_label || ': cannot add/change members');
    RETURN NEXT throws_ok('SELECT public.remove_institution_member(current_setting(''test.phase6_institution'')::uuid,
        ''60000000-0000-4000-8000-000000000005'')',
        '42501','Institution administration is not permitted',p_label || ': cannot remove members');
    RETURN NEXT throws_ok('UPDATE public.institutions SET verification_status=''verified''',
        '42501',NULL,p_label || ': direct status update denied');
    RETURN NEXT throws_ok('UPDATE public.institution_members SET role=''owner''',
        '42501',NULL,p_label || ': direct membership update denied');
    RETURN NEXT throws_ok('DELETE FROM public.institution_members',
        '42501',NULL,p_label || ': direct membership delete denied');
    RETURN NEXT throws_ok('DELETE FROM public.institutions',
        '42501',NULL,p_label || ': institution delete denied');
    RESET ROLE;
END;
$$;
SELECT * FROM pg_temp.phase6_denied_manager('60000000-0000-4000-8000-000000000004','Institution admin');
SELECT * FROM pg_temp.phase6_denied_manager('60000000-0000-4000-8000-000000000005','Issuer');
SELECT * FROM pg_temp.phase6_denied_manager('60000000-0000-4000-8000-000000000006','Unaffiliated institution_admin');
SELECT * FROM pg_temp.phase6_denied_manager('60000000-0000-4000-8000-000000000007','Holder without membership');
SELECT * FROM pg_temp.phase6_denied_manager('60000000-0000-4000-8000-000000000003','Owner of another institution');

SELECT pg_temp.phase6_actor('60000000-0000-4000-8000-000000000004');
SET LOCAL ROLE authenticated;
SELECT lives_ok($sql$ SELECT public.update_institution_details(current_setting('test.phase6_institution')::uuid,
    'Synthetic Admin Edit','phase6-main')
$sql$, 'Institution admin may edit details');
RESET ROLE;
SELECT pg_temp.phase6_actor('60000000-0000-4000-8000-000000000005');
SET LOCAL ROLE authenticated;
SELECT throws_ok($sql$ SELECT public.update_institution_details(current_setting('test.phase6_institution')::uuid,
    'Synthetic Denied','phase6-main')
$sql$, '42501', 'Institution administration is not permitted', 'Issuer cannot edit details');
RESET ROLE;

SELECT pg_temp.phase6_actor('60000000-0000-4000-8000-000000000001');
SET LOCAL ROLE authenticated;
SELECT lives_ok($sql$ SELECT public.set_institution_status(current_setting('test.phase6_institution')::uuid,'rejected')
$sql$, 'Platform admin can reject pending institution');
SELECT is((SELECT verification_status::text FROM public.institutions WHERE slug='phase6-main'),'rejected','Rejected persisted');
SELECT throws_ok($sql$ SELECT public.set_institution_status(current_setting('test.phase6_institution')::uuid,'verified')
$sql$, '22023', 'Invalid institution status transition', 'Rejected must pass through re-review');
SELECT lives_ok($sql$ SELECT public.set_institution_status(current_setting('test.phase6_institution')::uuid,'pending')
$sql$, 'Platform admin can reopen review');
SELECT throws_ok($sql$ SELECT public.set_institution_status(current_setting('test.phase6_institution')::uuid,'suspended')
$sql$, '22023', NULL, 'Pending cannot be suspended before approval');
SELECT lives_ok($sql$ SELECT public.set_institution_status(current_setting('test.phase6_institution')::uuid,'verified')
$sql$, 'Platform admin can approve pending');
SELECT is((SELECT verification_status::text FROM public.institutions WHERE slug='phase6-main'),'verified','Verified persisted');
SELECT lives_ok($sql$ SELECT public.set_institution_status(current_setting('test.phase6_institution')::uuid,'verified')
$sql$, 'Same-status retry is idempotent');
SELECT throws_ok($sql$ SELECT public.set_institution_status(current_setting('test.phase6_institution')::uuid,'rejected')
$sql$, '22023', NULL, 'Verified cannot skip suspension');
SELECT throws_ok($sql$ SELECT public.set_institution_status(current_setting('test.phase6_institution')::uuid,NULL)
$sql$, '22023', NULL, 'Null status rejected');
SELECT lives_ok($sql$ SELECT public.set_institution_status(current_setting('test.phase6_institution')::uuid,'suspended')
$sql$, 'Platform admin can suspend verified');
SELECT is((SELECT verification_status::text FROM public.institutions WHERE slug='phase6-main'),'suspended','Suspended persisted');
SELECT throws_ok($sql$ SELECT public.set_institution_status(current_setting('test.phase6_institution')::uuid,'verified')
$sql$, '22023', NULL, 'Suspended requires new pending review');
SELECT lives_ok($sql$ SELECT public.set_institution_member(current_setting('test.phase6_institution')::uuid,
    '60000000-0000-4000-8000-000000000007','owner')
$sql$, 'Platform admin may add second owner even while suspended');
SELECT throws_ok($sql$ DELETE FROM public.institutions WHERE slug='phase6-main'
$sql$, '42501', NULL, 'API platform admin cannot delete institution');
RESET ROLE;

SELECT pg_temp.phase6_actor('60000000-0000-4000-8000-000000000002');
SET LOCAL ROLE authenticated;
SELECT lives_ok($sql$ SELECT public.set_institution_member(current_setting('test.phase6_institution')::uuid,auth.uid(),'admin')
$sql$, 'One of two owners may demote self');
SELECT throws_ok($sql$ SELECT public.remove_institution_member(current_setting('test.phase6_institution')::uuid,
    '60000000-0000-4000-8000-000000000007')
$sql$, '42501', NULL, 'Demoted owner immediately loses membership management');
RESET ROLE;
SELECT pg_temp.phase6_actor('60000000-0000-4000-8000-000000000007');
SET LOCAL ROLE authenticated;
SELECT lives_ok($sql$ SELECT public.set_institution_member(current_setting('test.phase6_institution')::uuid,
    '60000000-0000-4000-8000-000000000005','admin')
$sql$, 'Remaining owner may change issuer to admin');
SELECT lives_ok($sql$ SELECT public.remove_institution_member(current_setting('test.phase6_institution')::uuid,
    '60000000-0000-4000-8000-000000000005')
$sql$, 'Remaining owner may remove admin');
SELECT lives_ok($sql$ SELECT public.remove_institution_member(current_setting('test.phase6_institution')::uuid,
    '60000000-0000-4000-8000-000000000005')
$sql$, 'Repeated removal is idempotent');
RESET ROLE;

SELECT throws_ok($sql$ DELETE FROM public.profiles WHERE id='60000000-0000-4000-8000-000000000007'
$sql$, '23514', 'Institution must retain an owner', 'Profile cascade cannot remove last owner');
SELECT throws_ok($sql$ DELETE FROM auth.users WHERE id='60000000-0000-4000-8000-000000000007'
$sql$, '23514', 'Institution must retain an owner', 'Auth cascade cannot remove last owner');
SELECT throws_ok($sql$ UPDATE public.institution_members SET user_id='60000000-0000-4000-8000-000000000009'
    WHERE institution_id=current_setting('test.phase6_institution')::uuid AND role='owner'
$sql$, '23514', 'Membership identity is immutable', 'Trusted SQL cannot reassign membership identity');
SELECT throws_ok($sql$ DELETE FROM public.institutions WHERE slug='phase6-main'
$sql$, '42501', 'Institution deletion is disabled; use verification status', 'Even trusted ordinary SQL cannot delete institution');
SELECT lives_ok('SET CONSTRAINTS ALL IMMEDIATE','All institutions have owners at final constraint check');
SELECT throws_ok('TRUNCATE public.institution_members','42501','Institution truncation is disabled',
    'Trusted TRUNCATE cannot bypass owner row triggers');
SELECT throws_ok('TRUNCATE public.institutions CASCADE','42501','Institution truncation is disabled',
    'Trusted TRUNCATE CASCADE cannot delete institutional history');
SELECT throws_ok('TRUNCATE public.profiles CASCADE','42501','Institution truncation is disabled',
    'Trusted profile truncation cannot cascade through memberships');
SELECT pg_temp.phase6_actor('60000000-0000-4000-8000-000000000001');
SET LOCAL ROLE authenticated;
SELECT throws_ok($sql$ SELECT public.remove_institution_member(current_setting('test.phase6_institution')::uuid,
    '60000000-0000-4000-8000-000000000007')
$sql$, '23514', 'Institution must retain an owner', 'Platform admin cannot remove last owner');
SELECT throws_ok($sql$ SELECT public.set_institution_member(current_setting('test.phase6_institution')::uuid,
    '60000000-0000-4000-8000-000000000007','issuer')
$sql$, '23514', 'Institution must retain an owner', 'Platform admin cannot demote last owner');
RESET ROLE;

-- Exercise the same authorization rules in every real institutional state.
CREATE FUNCTION pg_temp.phase6_state(p_state public.institution_verification_status)
RETURNS SETOF text LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
    PERFORM pg_temp.phase6_actor('60000000-0000-4000-8000-000000000001');
    UPDATE public.institutions SET verification_status=p_state
        WHERE id=current_setting('test.phase6_institution')::uuid; -- Trusted test setup only.
    PERFORM pg_temp.phase6_actor('60000000-0000-4000-8000-000000000007');
    SET LOCAL ROLE authenticated;
    RETURN NEXT is((SELECT verification_status FROM public.institutions
        WHERE id=current_setting('test.phase6_institution')::uuid),p_state,p_state || ': exact state');
    RETURN NEXT lives_ok('SELECT public.set_institution_member(current_setting(''test.phase6_institution'')::uuid,
        ''60000000-0000-4000-8000-000000000009'',''issuer'')',p_state || ': owner can add member');
    RETURN NEXT lives_ok('SELECT public.remove_institution_member(current_setting(''test.phase6_institution'')::uuid,
        ''60000000-0000-4000-8000-000000000009'')',p_state || ': owner can remove non-owner');
    RETURN NEXT throws_ok('SELECT public.set_institution_status(current_setting(''test.phase6_institution'')::uuid,''verified'')',
        '42501','Platform administration is required',p_state || ': owner cannot change status');
    RETURN NEXT throws_ok('INSERT INTO public.certificates(holder_id,institution_id,issued_by,title,credential_code)
        VALUES(auth.uid(),current_setting(''test.phase6_institution'')::uuid,auth.uid(),''Synthetic Denied'',''phase6-denied'')',
        '42501',NULL,p_state || ': institutional administration never enables issuance');
    RETURN NEXT throws_ok('UPDATE public.certificates SET status=''revoked'',revoked_at=now()',
        '42501',NULL,p_state || ': revocation remains closed');
    RESET ROLE;
END;
$$;
SELECT * FROM pg_temp.phase6_state('pending');
SELECT * FROM pg_temp.phase6_state('verified');
SELECT * FROM pg_temp.phase6_state('rejected');
SELECT * FROM pg_temp.phase6_state('suspended');

-- Prove RLS is a second barrier if table grants are accidentally restored.
GRANT INSERT, UPDATE, DELETE ON public.institutions, public.institution_members TO authenticated;
SELECT pg_temp.phase6_actor('60000000-0000-4000-8000-000000000001');
SET LOCAL ROLE authenticated;
SELECT throws_ok($sql$ INSERT INTO public.institutions(name,slug) VALUES('Synthetic Denied','phase6-rls-denied')
$sql$,'42501',NULL,'RLS rejects direct institution creation even for platform admin with grant');
SELECT throws_ok($sql$ INSERT INTO public.institution_members(institution_id,user_id,role)
    VALUES(current_setting('test.phase6_institution')::uuid,'60000000-0000-4000-8000-000000000009','owner')
$sql$,'42501',NULL,'RLS rejects direct membership creation even with grant');
WITH changed AS (UPDATE public.institutions SET verification_status='verified' RETURNING id)
SELECT is((SELECT count(*) FROM changed),0::bigint,'RLS hides all institution rows from direct UPDATE');
WITH changed AS (DELETE FROM public.institutions RETURNING id)
SELECT is((SELECT count(*) FROM changed),0::bigint,'RLS hides all institutions from DELETE');
WITH changed AS (UPDATE public.institution_members SET role='issuer' RETURNING id)
SELECT is((SELECT count(*) FROM changed),0::bigint,'RLS hides all members from direct UPDATE');
WITH changed AS (DELETE FROM public.institution_members RETURNING id)
SELECT is((SELECT count(*) FROM changed),0::bigint,'RLS hides all members from DELETE');
RESET ROLE;
REVOKE INSERT, UPDATE, DELETE ON public.institutions, public.institution_members FROM authenticated;

-- Catalog barriers and anonymous access. Certificate regressions remain in the
-- original 203 tests, including 4D reads in every institution state.
SELECT is((SELECT count(*) FROM pg_policy WHERE polrelid IN
    ('public.institutions'::regclass,'public.institution_members'::regclass) AND polcmd<>'r'),
    0::bigint,'Institution tables have only SELECT policies');
SELECT ok(NOT has_table_privilege(r,'public.' || t,'INSERT,UPDATE,DELETE,TRUNCATE,TRIGGER,REFERENCES')
    AND NOT has_any_column_privilege(r,'public.' || t,'INSERT,UPDATE,REFERENCES'),r || ': no direct writes to ' || t)
FROM (VALUES ('anon'),('authenticated')) AS roles(r)
CROSS JOIN (VALUES ('institutions'),('institution_members'),('certificates')) AS tables(t);
SELECT ok(has_function_privilege('authenticated',p.oid,'EXECUTE')
    AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
    AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')
    AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""'],p.proname || ': narrow RPC grants and fixed search path')
FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
    ('create_institution','update_institution_details','set_institution_status','set_institution_member','remove_institution_member');
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claims','{"role":"anon"}',true);
SET LOCAL ROLE anon;
SELECT is(current_user::text,'anon','Anonymous uses effective API role');
SELECT is((SELECT count(*) FROM public.institutions),0::bigint,'Anon reads no institutions');
SELECT is((SELECT count(*) FROM public.institution_members),0::bigint,'Anon reads no memberships');
SELECT throws_ok($sql$ SELECT public.create_institution('Synthetic Anon','phase6-anon',NULL)
$sql$,'42501',NULL,'Anon cannot execute creation RPC');
SELECT throws_ok($sql$ SELECT public.set_institution_status(NULL,'verified')
$sql$,'42501',NULL,'Anon cannot execute approval RPC');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
