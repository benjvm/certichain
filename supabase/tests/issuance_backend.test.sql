BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT no_plan();
INSERT INTO auth.users (id, raw_user_meta_data, email_confirmed_at) VALUES
('7c000000-0000-4000-8000-000000000001', '{"full_name":"Synthetic Issuer"}', now()),
('7c000000-0000-4000-8000-000000000002', '{"full_name":"Synthetic Holder"}', now()),
('7c000000-0000-4000-8000-000000000003', '{"full_name":"Synthetic Other"}', now()),
('7c000000-0000-4000-8000-000000000004', '{"full_name":"Synthetic Platform"}', now());
SELECT certichain_private.grant_platform_admin('7c000000-0000-4000-8000-000000000004',
    '7c000000-0000-4000-8000-000000000004', 0);
INSERT INTO public.institutions (id, name, slug, verification_status) VALUES
('7c000000-0000-4000-8000-000000000011', 'Synthetic Backend', 'phase7b-sql', 'verified');
INSERT INTO public.institution_members (institution_id, user_id, role) VALUES
('7c000000-0000-4000-8000-000000000011', '7c000000-0000-4000-8000-000000000001', 'owner'),
('7c000000-0000-4000-8000-000000000011', '7c000000-0000-4000-8000-000000000003', 'issuer');

SELECT ok(NOT has_function_privilege('anon', p.oid, 'EXECUTE')
    AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
    AND has_function_privilege('service_role', p.oid, 'EXECUTE'),
    'Only technical role can call ' || p.proname)
FROM pg_proc AS p JOIN pg_namespace AS n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname IN ('reserve_certificate_issuance', 'advance_certificate_issuance');
SET LOCAL ROLE authenticated;
SELECT throws_ok($$ SELECT public.reserve_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', '7c000000-0000-4000-8000-000000000001',
    '7c000000-0000-4000-8000-000000000002', gen_random_uuid(), repeat('a',64), repeat('b',64), 'Title') $$,
    '42501', NULL, 'Client cannot impersonate an actor via reservation RPC');
RESET ROLE;
CREATE TEMP TABLE lease AS SELECT public.reserve_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', '7c000000-0000-4000-8000-000000000001',
    '7c000000-0000-4000-8000-000000000002', '7c000000-0000-4000-8000-000000000041',
    repeat('a',64), repeat('b',64), 'Title') AS result;
SELECT is((SELECT result->>'status' FROM lease), 'uploading', 'Reservation acquires upload lease');
SELECT is(public.reserve_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', '7c000000-0000-4000-8000-000000000001',
    '7c000000-0000-4000-8000-000000000002', '7c000000-0000-4000-8000-000000000041',
    repeat('a',64), repeat('b',64), 'Title')->>'status', 'in_progress', 'Live lease cannot be reacquired');
SELECT throws_ok($$ SELECT public.reserve_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', '7c000000-0000-4000-8000-000000000003',
    '7c000000-0000-4000-8000-000000000002', '7c000000-0000-4000-8000-000000000041',
    repeat('a',64), repeat('b',64), 'Title') $$, '23505', 'idempotency_conflict', 'Different actor conflicts');
SELECT throws_ok($$ UPDATE public.certificate_issuance_operations SET title = 'Changed' $$,
    '23514', 'Issuance metadata is immutable', 'Metadata preserved across leases');
SELECT throws_ok($$ SELECT public.advance_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', (SELECT (result->>'operation_id')::uuid FROM lease),
    gen_random_uuid(), 'validate', repeat('b',64)) $$, 'PT409', 'lease_lost', 'Stale token fenced');
SELECT throws_ok($$ SELECT public.advance_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', (SELECT (result->>'operation_id')::uuid FROM lease),
    (SELECT (result->>'lease_token')::uuid FROM lease), 'validate', repeat('c',64)) $$,
    '22023', 'stored_hash_mismatch', 'Final bytes must match accepted input');
SELECT lives_ok($$ SELECT public.advance_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', (SELECT (result->>'operation_id')::uuid FROM lease),
    (SELECT (result->>'lease_token')::uuid FROM lease), 'validate', repeat('b',64)) $$, 'Stored hash validates');

-- Failure during the operation update must roll back the certificate INSERT too.
CREATE FUNCTION pg_temp.fail_completion() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF NEW.status = 'completed' THEN RAISE EXCEPTION 'Injected completion failure'; END IF; RETURN NEW; END;
$$;
CREATE TRIGGER injected_completion BEFORE UPDATE ON public.certificate_issuance_operations
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_completion();
SELECT throws_ok($$ SELECT public.advance_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', (SELECT (result->>'operation_id')::uuid FROM lease),
    (SELECT (result->>'lease_token')::uuid FROM lease), 'publish') $$,
    'P0001', 'Injected completion failure', 'Publication failure rolls back entire transaction');
SELECT is((SELECT count(*) FROM public.certificates), 0::bigint, 'No certificate from failed commit');
SELECT is((SELECT status FROM public.certificate_issuance_operations), 'finalizing', 'Recoverable state retained');
DROP TRIGGER injected_completion ON public.certificate_issuance_operations;
SELECT set_config('request.jwt.claim.sub', '7c000000-0000-4000-8000-000000000004', true);
UPDATE public.institutions SET verification_status = 'suspended';
SELECT throws_ok($$ SELECT public.advance_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', (SELECT (result->>'operation_id')::uuid FROM lease),
    (SELECT (result->>'lease_token')::uuid FROM lease), 'publish') $$,
    '42501', 'issuance_forbidden', 'Publication rechecks institutional state');
UPDATE public.institutions SET verification_status = 'verified';
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT lives_ok($$ SELECT public.advance_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', (SELECT (result->>'operation_id')::uuid FROM lease),
    (SELECT (result->>'lease_token')::uuid FROM lease), 'publish') $$, 'Publication commits certificate and completed together');
SELECT is((SELECT count(*) FROM public.certificates), 1::bigint, 'Exactly one certificate');
SELECT is((SELECT status FROM public.certificate_issuance_operations), 'completed', 'Operation completed');
SELECT is(public.advance_certificate_issuance('7c000000-0000-4000-8000-000000000011',
    (SELECT (result->>'operation_id')::uuid FROM lease), NULL, 'cleanup_claim')->>'status',
    'protected', 'Completed PDF never eligible for cleanup');
SELECT is(public.reserve_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', '7c000000-0000-4000-8000-000000000001',
    '7c000000-0000-4000-8000-000000000002', '7c000000-0000-4000-8000-000000000041',
    repeat('a',64), repeat('b',64), 'Title')->>'status', 'completed', 'Lost HTTP response recovers completed result');
SELECT lives_ok($$ UPDATE public.certificates SET status = 'revoked' $$, 'Historical revocation guard still allows trusted transition');
SELECT throws_ok($$ UPDATE public.certificates SET status = 'active', revoked_at = NULL $$,
    'P0001', 'Institution administrators may only revoke certificates', 'Revocation remains irreversible');

CREATE TEMP TABLE abandoned AS SELECT public.reserve_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', '7c000000-0000-4000-8000-000000000003',
    '7c000000-0000-4000-8000-000000000002', '7c000000-0000-4000-8000-000000000042',
    repeat('d',64), repeat('b',64), 'Title') AS result;
DELETE FROM public.institution_members WHERE user_id = '7c000000-0000-4000-8000-000000000003';
SELECT throws_ok($$ SELECT public.advance_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', (SELECT (result->>'operation_id')::uuid FROM abandoned),
    (SELECT (result->>'lease_token')::uuid FROM abandoned), 'publish') $$,
    '22023', 'invalid_transition', 'Cannot skip object validation');
SELECT lives_ok($$ SELECT public.advance_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', (SELECT (result->>'operation_id')::uuid FROM abandoned),
    (SELECT (result->>'lease_token')::uuid FROM abandoned), 'abandon') $$, 'Terminal cleanup persisted');
CREATE TEMP TABLE cleanup AS SELECT public.advance_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', (SELECT (result->>'operation_id')::uuid FROM abandoned),
    NULL, 'cleanup_claim') AS result;
SELECT lives_ok($$ SELECT public.advance_certificate_issuance(
    '7c000000-0000-4000-8000-000000000011', (SELECT (result->>'operation_id')::uuid FROM abandoned),
    (SELECT (result->>'lease_token')::uuid FROM cleanup), 'cleanup_done') $$, 'Confirmed deletion closes attempt');
SELECT is((SELECT status FROM public.certificate_issuance_operations WHERE id =
    (SELECT (result->>'operation_id')::uuid FROM abandoned)), 'failed', 'Cleanup terminal state');
SELECT * FROM finish();
ROLLBACK;

