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

SELECT ok(has_function_privilege('service_role',p.oid,'EXECUTE') AND
 NOT has_function_privilege('anon',p.oid,'EXECUTE') AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE'),
 'Technical-only RPC: '||p.proname) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
 WHERE n.nspname='public' AND p.proname IN ('lookup_public_certificate','consume_public_verification_budget');
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid,
 LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
 WHERE n.nspname='public' AND p.proname IN ('lookup_public_certificate','consume_public_verification_budget') AND acl.grantee=0), 'No PUBLIC EXECUTE');
SET LOCAL ROLE anon;
SELECT throws_ok($$SELECT public.lookup_public_certificate('8a000000-0000-4000-8000-000000000099')$$,'42501',NULL,'Anonymous cannot call technical lookup');
SELECT throws_ok($$SELECT public.consume_public_verification_budget()$$,'42501',NULL,'Anonymous cannot manipulate budget');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT throws_ok($$SELECT public.lookup_public_certificate('8a000000-0000-4000-8000-000000000099')$$,'42501',NULL,'Session cannot call technical lookup');
SELECT throws_ok($$SELECT public.consume_public_verification_budget()$$,'42501',NULL,'Session cannot manipulate budget');
RESET ROLE;
SELECT ok(NOT has_table_privilege(role,'certichain_private.public_verification_budget',priv),'Budget private: '||role||' '||priv)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) priv;
SELECT ok(NOT has_table_privilege('anon','public.certificates','SELECT') AND
 NOT has_table_privilege('authenticated','public.certificate_issuance_operations','SELECT') AND
 NOT has_table_privilege('authenticated','public.certificates','UPDATE'), 'Private table grants preserved');
SELECT ok((SELECT NOT public FROM storage.buckets WHERE id='certificates'), 'Private bucket preserved');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND policyname LIKE 'certificates_objects_no_client_%' AND permissive='RESTRICTIVE'),4::bigint,'Restrictive Storage policies preserved');
SELECT throws_ok($$SELECT public.lookup_public_certificate(NULL)$$,'22023','invalid_input','NULL rejected');
SELECT throws_ok($$SELECT public.lookup_public_certificate('not UUID')$$,'22023','invalid_input','Non-contract format rejected');
SELECT throws_ok($$SELECT public.lookup_public_certificate(E'8a000000-0000-4000-8000-000000000099\n')$$,'22023','invalid_input','Trailing newline rejected');
SELECT is(public.lookup_public_certificate(gen_random_uuid()::text),'{"schema_version":"1","result":"not_found"}'::jsonb,'Unknown minimal');
SELECT is(public.lookup_public_certificate('8a000000-0000-4000-8000-000000000099'),'{"schema_version":"1","result":"not_found"}'::jsonb,'Historical no evidence minimal');
SELECT is(public.lookup_public_certificate((SELECT incomplete FROM codes)),'{"schema_version":"1","result":"not_found"}'::jsonb,'Finalizing never public');
SELECT is(public.lookup_public_certificate((SELECT mismatch FROM codes)),'{"schema_version":"1","result":"not_found"}'::jsonb,'Incoherent PDF hash never public');
SELECT is(public.lookup_public_certificate((SELECT upper(valid) FROM codes))->>'result','valid','Uppercase equivalent eligible');
CREATE TEMP TABLE projection AS SELECT public.lookup_public_certificate((SELECT valid FROM codes)) AS data;
SELECT is((SELECT array_agg(k ORDER BY k) FROM projection,jsonb_object_keys(data) k),
 ARRAY['checked_at','credential_code','expires_at','issued_at','issuer','result','schema_version','title','verification_source'],'Closed field list');
SELECT is((SELECT data->'issuer' FROM projection),'{"name":"Public Issuer"}'::jsonb,'Only issuer name');
SELECT is((SELECT data->>'issued_at' FROM projection)::timestamptz,'2020-01-01T00:00:00.123456Z'::timestamptz,'Microseconds retained');
SELECT ok((SELECT data->'expires_at'='null'::jsonb FROM projection),'Nullable expiration');
SELECT is(public.lookup_public_certificate((SELECT expired FROM codes))->>'result','expired','Expired eligible');
SELECT is(certichain_private.public_verification_result(false,'2026-10-04T12:00:00.123456Z',true,'2026-10-04T12:00:00.123456Z'),'expired','Exact expiry equality');
SELECT is(certichain_private.public_verification_result(false,'2026-10-04T12:00:00.123456Z',true,'2026-10-04T12:00:00.123455Z'),'valid','One microsecond before expiry');
SELECT set_config('request.jwt.claim.sub','8a000000-0000-4000-8000-000000000004',true);
UPDATE public.institutions SET verification_status='suspended' WHERE id='8a000000-0000-4000-8000-000000000011';
SELECT is(public.lookup_public_certificate((SELECT valid FROM codes))->>'result','issuer_unavailable','Suspension independent of revocation');
SELECT is(public.lookup_public_certificate((SELECT expired FROM codes))->>'result','expired','Expiry before issuer status');
SELECT set_config('request.jwt.claim.sub','',true);
UPDATE public.certificates SET status='revoked' WHERE credential_code=(SELECT expired FROM codes);
SELECT is(public.lookup_public_certificate((SELECT expired FROM codes))->>'result','revoked','Revocation before expiry and suspension');
SELECT is((SELECT count(*) FROM snapshot s JOIN public.certificates c USING(id)
 WHERE c.credential_code<>(SELECT expired FROM codes) AND to_jsonb(c) IS DISTINCT FROM s.row),0::bigint,'Repeated reads preserve full historical/issued rows');
SELECT throws_ok($$UPDATE public.certificates SET credential_code=gen_random_uuid()::text WHERE issuance_operation_id IS NOT NULL$$,NULL,NULL,'Published code immutable');
SELECT throws_ok($$UPDATE public.certificate_issuance_operations SET holder_id='8a000000-0000-4000-8000-000000000003'$$,'23514',NULL,'Mismatched links rejected by integrity');
SELECT throws_ok($$INSERT INTO public.certificates(institution_id,holder_id,issued_by,title,credential_code)
 SELECT institution_id,holder_id,issued_by,title,credential_code FROM public.certificates LIMIT 1$$,
 '23505',NULL,'Code uniqueness preserved independently of internal ID');

SET LOCAL ROLE service_role;
SELECT is(public.lookup_public_certificate('8a000000-0000-4000-8000-000000000099')->>'result','not_found','Technical role actually executes');
SELECT is(public.consume_public_verification_budget(),'{"allowed":true,"retry_after":0}'::jsonb,'Technical role consumes');
RESET ROLE;
UPDATE certichain_private.public_verification_budget SET used=59,window_started_at=clock_timestamp();
SELECT is(public.consume_public_verification_budget()->>'allowed','true','Last slot granted');
SELECT is(public.consume_public_verification_budget()->>'allowed','false','Exhaustion denied');
SELECT ok((public.consume_public_verification_budget()->>'retry_after')::integer BETWEEN 1 AND 60,'Retry from server clock');
SELECT is((SELECT used FROM certichain_private.public_verification_budget),60,'No over-allocation');
UPDATE certichain_private.public_verification_budget SET window_started_at=clock_timestamp()-interval '60 seconds';
SELECT is(public.consume_public_verification_budget()->>'allowed','true','Window renewal without sleeping');
SELECT is((SELECT used FROM certichain_private.public_verification_budget),1,'Renewal reuses row');
SELECT is((SELECT count(*) FROM certichain_private.public_verification_budget),1::bigint,'Bounded storage');
DELETE FROM certichain_private.public_verification_budget;
SELECT throws_ok($$SELECT public.consume_public_verification_budget()$$,'P0002',NULL,'Missing limiter row fails closed');
SELECT * FROM finish();
ROLLBACK;
