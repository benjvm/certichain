BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT no_plan();
INSERT INTO auth.users(id,raw_user_meta_data,email_confirmed_at) VALUES
('8a000000-0000-4000-8000-000000000001','{"full_name":"Synthetic Issuer"}',now()),
('8a000000-0000-4000-8000-000000000002','{"full_name":"Private Holder"}',now()),
('8a000000-0000-4000-8000-000000000003','{"full_name":"Other Holder"}',now()),
('8a000000-0000-4000-8000-000000000004','{"full_name":"Synthetic Platform"}',now());
SELECT certichain_private.grant_platform_admin('8a000000-0000-4000-8000-000000000004',
 '8a000000-0000-4000-8000-000000000004',0);
INSERT INTO public.institutions(id,name,slug,verification_status) VALUES
('8a000000-0000-4000-8000-000000000011','Public Issuer','phase8a-sql','verified');
INSERT INTO public.institution_members(institution_id,user_id,role) VALUES
('8a000000-0000-4000-8000-000000000011','8a000000-0000-4000-8000-000000000001','owner');

-- Synthetic passage-of-time fixtures: valid dates at original publication,
-- finalizing -> completed, all constraints and production guards remain enabled.
CREATE FUNCTION pg_temp.published(p_expires timestamptz, p_pdf_hash text DEFAULT repeat('b',64), p_completed boolean DEFAULT true)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE op uuid := gen_random_uuid(); cert uuid := gen_random_uuid(); code text := gen_random_uuid()::text;
BEGIN
 INSERT INTO public.certificate_issuance_operations(id,institution_id,actor_id,holder_id,idempotency_key,
 request_fingerprint,pdf_hash,target_certificate_id,stored_hash,status,title,expires_at)
 VALUES(op,'8a000000-0000-4000-8000-000000000011','8a000000-0000-4000-8000-000000000001',
 '8a000000-0000-4000-8000-000000000002',gen_random_uuid(),repeat('a',64),p_pdf_hash,cert,repeat('b',64),'finalizing','Public Title',p_expires);
 INSERT INTO public.certificates(id,institution_id,issued_by,holder_id,title,description,credential_code,
 issued_at,expires_at,document_path,document_hash,issuance_operation_id)
 VALUES(cert,'8a000000-0000-4000-8000-000000000011','8a000000-0000-4000-8000-000000000001',
 '8a000000-0000-4000-8000-000000000002','Public Title','PRIVATE DESCRIPTION',code,
 '2020-01-01T00:00:00.123456Z',p_expires,'8a000000-0000-4000-8000-000000000011/'||cert::text||'.pdf',repeat('b',64),op);
 IF p_completed THEN UPDATE public.certificate_issuance_operations SET status='completed',certificate_id=cert WHERE id=op; END IF;
 RETURN code;
END;
$$;
CREATE TEMP TABLE codes AS SELECT pg_temp.published(NULL) AS valid,
 pg_temp.published('2021-01-01T00:00:00.654321Z') AS expired,
 pg_temp.published(NULL,repeat('c',64)) AS mismatch,
 pg_temp.published(NULL,repeat('b',64),false) AS incomplete;
INSERT INTO public.certificates(institution_id,holder_id,issued_by,title,credential_code,document_path,document_hash)
 VALUES('8a000000-0000-4000-8000-000000000011','8a000000-0000-4000-8000-000000000002',
 '8a000000-0000-4000-8000-000000000001','Legacy','8a000000-0000-4000-8000-000000000099','old/path','UNKNOWN HASH');
CREATE TEMP TABLE snapshot AS SELECT id,to_jsonb(c) AS row FROM public.certificates c;


SELECT ok(has_function_privilege('service_role','public.compare_public_certificate_hash(text,text)','EXECUTE'), 'Service role comparison');
SELECT ok(NOT has_function_privilege(role,'public.compare_public_certificate_hash(text,text)','EXECUTE'), 'Comparison denied: '||role) FROM unnest(ARRAY['anon','authenticated']) role;
SELECT ok(NOT has_function_privilege(role,'certichain_private.public_certificate_snapshot(text)','EXECUTE'), 'Private snapshot denied: '||role) FROM unnest(ARRAY['anon','authenticated','service_role']) role;
SELECT ok(p.prosecdef AND p.proconfig @> ARRAY['search_path=""'], 'Technical definer with empty search_path') FROM pg_proc p WHERE p.oid='public.compare_public_certificate_hash(text,text)'::regprocedure;
SET LOCAL ROLE anon;
SELECT throws_ok($$SELECT public.compare_public_certificate_hash('8a000000-0000-4000-8000-000000000099',repeat('b',64))$$,'42501',NULL,'Anon RPC denied');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT throws_ok($$SELECT public.compare_public_certificate_hash('8a000000-0000-4000-8000-000000000099',repeat('b',64))$$,'42501',NULL,'Authenticated RPC denied');
RESET ROLE;
SELECT throws_ok(format('SELECT public.compare_public_certificate_hash(%L,%L)',(SELECT valid FROM codes),bad),'22023','invalid_input','Invalid canonical digest') FROM unnest(ARRAY[NULL,'',repeat('B',64),repeat('b',63),repeat('b',65),repeat('b',64)||E'\n']) bad;
SELECT throws_ok($$SELECT public.compare_public_certificate_hash('not-code',repeat('b',64))$$,'22023','invalid_input','Invalid code');
SELECT is(public.compare_public_certificate_hash(code,repeat('b',64)), '{"schema_version":"1","verification":{"schema_version":"1","result":"not_found"},"file_integrity":"unavailable"}'::jsonb,'Uniform unavailable') FROM (SELECT incomplete AS code FROM codes UNION ALL SELECT mismatch FROM codes UNION ALL SELECT '8a000000-0000-4000-8000-000000000099' UNION ALL SELECT gen_random_uuid()::text) cases;
CREATE FUNCTION pg_temp.check_comparison(p_code text,p_result text) RETURNS SETOF text LANGUAGE plpgsql AS $$
DECLARE data jsonb; candidate text;
BEGIN
 FOR candidate IN SELECT unnest(ARRAY[repeat('b',64),repeat('c',64)]) LOOP
  data := public.compare_public_certificate_hash(p_code,candidate);
  RETURN NEXT is(data->>'file_integrity',CASE WHEN candidate=repeat('b',64) THEN 'match' ELSE 'integrity_mismatch' END,'Integrity independent: '||p_result);
  RETURN NEXT is(data->'verification'->>'result',p_result,'Current certificate state: '||p_result);
  RETURN NEXT is((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(data) k),ARRAY['file_integrity','schema_version','verification'],'Closed comparison DTO');
  RETURN NEXT ok(NOT (data->'verification' ? 'document_hash') AND NOT (data ? 'expected_hash'),'Expected hash remains backend-only');
 END LOOP;
END;
$$;
SELECT pg_temp.check_comparison((SELECT valid FROM codes),'valid');
SELECT pg_temp.check_comparison((SELECT expired FROM codes),'expired');
SELECT set_config('request.jwt.claim.sub','8a000000-0000-4000-8000-000000000004',true);
UPDATE public.institutions SET verification_status='suspended' WHERE id='8a000000-0000-4000-8000-000000000011';
SELECT pg_temp.check_comparison((SELECT valid FROM codes),'issuer_unavailable');
SELECT set_config('request.jwt.claim.sub','',true);
UPDATE public.certificates SET status='revoked' WHERE credential_code=(SELECT expired FROM codes);
SELECT pg_temp.check_comparison((SELECT expired FROM codes),'revoked');
SELECT ok(NOT has_table_privilege('anon','public.certificates','SELECT') AND NOT has_table_privilege('authenticated','public.certificate_issuance_operations','SELECT') AND NOT has_table_privilege('authenticated','public.certificates','UPDATE'), 'Private table grants unchanged');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND policyname LIKE 'certificates_objects_no_client_%' AND permissive='RESTRICTIVE'),4::bigint,'Storage policies preserved');
SELECT * FROM finish();
ROLLBACK;
