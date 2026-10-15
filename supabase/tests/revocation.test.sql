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

INSERT INTO public.institution_members(institution_id,user_id,role) VALUES
('8a000000-0000-4000-8000-000000000011','8a000000-0000-4000-8000-000000000003','admin');
CREATE TEMP TABLE fixture AS SELECT c.id,c.credential_code,to_jsonb(c) AS before FROM public.certificates c WHERE false;
SELECT pg_temp.published(NULL);
INSERT INTO fixture SELECT c.id,c.credential_code,to_jsonb(c) FROM public.certificates c;
CREATE TEMP TABLE result AS SELECT public.request_certificate_revocation('8a000000-0000-4000-8000-000000000001',id,'aa000000-0000-4000-8000-000000000001',E'  Revisio\u0301n\r\nprivada  ') AS dto FROM fixture;
SELECT is((SELECT dto->>'status' FROM result),'revoked','SQL immediately revoked');
SELECT is((SELECT reason FROM certichain_private.certificate_revocations),E'Revisión\nprivada','NFC/newline/trim canonical private text');
SELECT is((SELECT dto->>'created' FROM result),'true','One logical decision');
SELECT ok((SELECT (dto->>'revoked_at')::timestamptz=now() FROM result),'Server date');
SELECT is((SELECT to_jsonb(c)-ARRAY['status','revoked_at','updated_at'] FROM public.certificates c JOIN fixture f ON f.id=c.id),(SELECT before-ARRAY['status','revoked_at','updated_at'] FROM fixture),'Published identity, metadata and document preserved');
SELECT is(public.lookup_public_certificate((SELECT credential_code FROM fixture))->>'result','revoked','Public SQL immediately revoked');
SELECT is(public.request_certificate_revocation('8a000000-0000-4000-8000-000000000001',(SELECT id FROM fixture),'aa000000-0000-4000-8000-000000000001',E'Revisión\nprivada')->>'created','false','Canonical same key recovers');
SELECT throws_ok($$SELECT public.request_certificate_revocation('8a000000-0000-4000-8000-000000000001',(SELECT id FROM fixture),'aa000000-0000-4000-8000-000000000001','Changed')$$,'23505','idempotency_conflict','Same key with different reason conflicts');
SELECT is(public.request_certificate_revocation('8a000000-0000-4000-8000-000000000003',(SELECT id FROM fixture),'aa000000-0000-4000-8000-000000000002','New key reason')->>'request_id',(SELECT dto->>'request_id' FROM result),'Admin/new key gets original logical decision');
SELECT is((SELECT count(*) FROM certichain_private.certificate_revocations),1::bigint,'No duplicate decision');
SELECT is((SELECT reason FROM certichain_private.certificate_revocations),E'Revisión\nprivada','Original reason preserved');
SELECT is((SELECT count(*) FROM certichain_private.certificate_anchors),0::bigint,'No off-chain anchor or salt');
SELECT is((SELECT count(*) FROM certichain_private.blockchain_operations),0::bigint,'No off-chain transaction');
SELECT throws_ok($$SELECT public.certificate_revocation_progress('8a000000-0000-4000-8000-000000000002',(SELECT id FROM fixture))$$,'PT404','revocation_unavailable','Holder denied');
SELECT throws_ok($$SELECT public.certificate_revocation_progress('8a000000-0000-4000-8000-000000000004',(SELECT id FROM fixture))$$,'PT404','revocation_unavailable','Platform without membership denied');
SELECT throws_ok($$SELECT public.certificate_revocation_progress('8a000000-0000-4000-8000-000000000001',gen_random_uuid())$$,'PT404','revocation_unavailable','Unknown same safe error');
SELECT set_config('request.jwt.claim.sub','8a000000-0000-4000-8000-000000000004',true);
UPDATE public.institutions SET verification_status='suspended';
SELECT is(public.certificate_revocation_progress('8a000000-0000-4000-8000-000000000003',(SELECT id FROM fixture))->>'status','revoked','Suspended admin can inspect audit');
UPDATE public.institutions SET verification_status='pending';
SELECT throws_ok($$SELECT public.certificate_revocation_progress('8a000000-0000-4000-8000-000000000001',(SELECT id FROM fixture))$$,'PT404','revocation_unavailable','Pending owner denied');
UPDATE public.institutions SET verification_status='rejected';
SELECT throws_ok($$SELECT public.certificate_revocation_progress('8a000000-0000-4000-8000-000000000001',(SELECT id FROM fixture))$$,'PT404','revocation_unavailable','Rejected owner denied');
SELECT throws_ok($$UPDATE public.certificates SET status='active',revoked_at=NULL$$,'P0001','Institution administrators may only revoke certificates','Irreversible even trusted SQL');
SELECT throws_ok($$UPDATE public.certificates SET revoked_at=now()+interval '1 second'$$,'P0001','Institution administrators may only revoke certificates','Original date immutable');
SELECT throws_ok($$UPDATE certichain_private.certificate_revocations SET reason='Changed'$$,'23514','revocation_history_protected','Audit immutable');
SELECT throws_ok($$DELETE FROM certichain_private.certificate_revocations$$,'23514','revocation_history_protected','Audit retained');
SELECT ok(NOT has_table_privilege(r,t,p),'No '||r||' '||p||' '||t) FROM unnest(ARRAY['anon','authenticated','service_role']) r CROSS JOIN unnest(ARRAY['certichain_private.certificate_revocations','certichain_private.certificate_revocation_keys']) t CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p;
SELECT * FROM finish();
ROLLBACK;
