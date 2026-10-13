BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET LOCAL search_path=public,extensions;
SELECT no_plan();
SELECT unnest(ARRAY[ok(p.prosecdef,'Technical definer: '||p.proname),ok(p.proconfig @> ARRAY['search_path=""'],'Empty path: '||p.proname),
  ok(has_function_privilege('service_role',p.oid,'EXECUTE'),'Service RPC: '||p.proname),
  ok(NOT has_function_privilege('anon',p.oid,'EXECUTE'),'Anon denied: '||p.proname),
  ok(NOT has_function_privilege('authenticated',p.oid,'EXECUTE'),'Client denied: '||p.proname)])
FROM pg_proc p WHERE p.oid IN ('public.lookup_public_certificate_v2(text,text)'::regprocedure,'public.authorize_certificate_opening(uuid,uuid,text)'::regprocedure);
INSERT INTO auth.users(id,raw_user_meta_data,email_confirmed_at) VALUES
('9d000000-0000-4000-8000-000000000001','{"full_name":"Synthetic Owner"}',now()),
('9d000000-0000-4000-8000-000000000002','{"full_name":"Synthetic Holder"}',now()),
('9d000000-0000-4000-8000-000000000003','{"full_name":"Synthetic Other"}',now()),
('9d000000-0000-4000-8000-000000000004','{"full_name":"Synthetic Platform"}',now());
SELECT certichain_private.grant_platform_admin('9d000000-0000-4000-8000-000000000004','9d000000-0000-4000-8000-000000000004',0);
INSERT INTO public.institutions(id,name,slug,verification_status) VALUES('9d000000-0000-4000-8000-000000000011','Synthetic','phase9d-sql','verified');
INSERT INTO public.institution_members(institution_id,user_id,role) VALUES('9d000000-0000-4000-8000-000000000011','9d000000-0000-4000-8000-000000000001','owner');
INSERT INTO public.institutions(id,name,slug,verification_status) VALUES('9d000000-0000-4000-8000-000000000012','Other Synthetic','phase9d-other','verified');
INSERT INTO public.institution_members(institution_id,user_id,role) VALUES('9d000000-0000-4000-8000-000000000012','9d000000-0000-4000-8000-000000000003','owner');
CREATE FUNCTION pg_temp.published(completed boolean DEFAULT true) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE op uuid:=gen_random_uuid(); cert uuid:=gen_random_uuid();
BEGIN
 INSERT INTO public.certificate_issuance_operations(id,institution_id,actor_id,holder_id,idempotency_key,request_fingerprint,pdf_hash,target_certificate_id,stored_hash,status,title)
 VALUES(op,'9d000000-0000-4000-8000-000000000011','9d000000-0000-4000-8000-000000000001','9d000000-0000-4000-8000-000000000002',gen_random_uuid(),repeat('a',64),repeat('b',64),cert,repeat('b',64),'finalizing','Synthetic');
 INSERT INTO public.certificates(id,institution_id,issued_by,holder_id,title,credential_code,document_path,document_hash,issuance_operation_id)
 VALUES(cert,'9d000000-0000-4000-8000-000000000011','9d000000-0000-4000-8000-000000000001','9d000000-0000-4000-8000-000000000002','Synthetic',gen_random_uuid()::text,'9d000000-0000-4000-8000-000000000011/'||cert||'.pdf',repeat('b',64),op);
 IF completed THEN UPDATE public.certificate_issuance_operations SET status='completed',certificate_id=cert WHERE id=op; END IF;
 RETURN cert;
END $$;
CREATE TEMP TABLE ids AS SELECT pg_temp.published() valid,pg_temp.published(false) incomplete;
INSERT INTO public.certificates(id,institution_id,issued_by,holder_id,title,credential_code) VALUES('9d000000-0000-4000-8000-000000000099','9d000000-0000-4000-8000-000000000011','9d000000-0000-4000-8000-000000000001','9d000000-0000-4000-8000-000000000002','Legacy','9d000000-0000-4000-8000-000000000099');
SELECT is((public.lookup_public_certificate_v2(c.credential_code,'local')->'registry')-'checked_at',public.lookup_public_certificate(c.credential_code)-'checked_at','Registry v1 literal') FROM public.certificates c WHERE c.id=(SELECT valid FROM ids);
SELECT is(public.lookup_public_certificate_v2(c.credential_code,'local')->'anchor','null'::jsonb,'Published without anchor has no technical evidence') FROM public.certificates c WHERE c.id=(SELECT valid FROM ids);
SELECT is(public.lookup_public_certificate_v2(code,'local'),'{"registry":{"schema_version":"1","result":"not_found"},"anchor":null}'::jsonb,'Uniform absence/legacy/incomplete') FROM (
 SELECT gen_random_uuid()::text code UNION ALL SELECT '9d000000-0000-4000-8000-000000000099' UNION ALL SELECT credential_code FROM public.certificates WHERE id=(SELECT incomplete FROM ids)) x;
CREATE TEMP TABLE deployment AS SELECT public.blockchain_register_deployment(jsonb_build_object('synthetic',false,'environmentId','local','network','anvil','chainId','31337','contractAddress','0x'||repeat('11',20),'protocolVersion',1,'genesisHash','0x'||repeat('22',32),'runtimeCodeHash','0x'||repeat('33',32),'deploymentBlock',jsonb_build_object('number','1','hash','0x'||repeat('44',32)))) id;
INSERT INTO certichain_private.blockchain_issuers(id,deployment_id,institution_id,issuer_id,signer,desired_can_issue,desired_can_revoke)
 SELECT '9d000000-0000-4000-8000-000000000022',id,'9d000000-0000-4000-8000-000000000011',decode(repeat('55',32),'hex'),decode(repeat('66',20),'hex'),true,true FROM deployment;
INSERT INTO certichain_private.certificate_anchors(certificate_id,issuance_operation_id,institution_id,deployment_id,issuer_binding_id,credential_code_snapshot,certificate_key,document_sha256,salt,commitment)
 SELECT c.id,c.issuance_operation_id,c.institution_id,d.id,'9d000000-0000-4000-8000-000000000022',c.credential_code::uuid,k,decode(c.document_hash,'hex'),s,
 extensions.digest(convert_to('certichain:document-commitment:v1','UTF8')||decode('00','hex')||k||decode(repeat('55',32),'hex')||decode(c.document_hash,'hex')||s,'sha256')
 FROM public.certificates c CROSS JOIN deployment d CROSS JOIN LATERAL (SELECT extensions.digest(convert_to('certichain:certificate-key:v1','UTF8')||decode('00','hex')||uuid_send(c.credential_code::uuid),'sha256') k,decode(repeat('77',32),'hex') s) v WHERE c.id=(SELECT valid FROM ids);
INSERT INTO certichain_private.blockchain_operations(anchor_id,issuer_binding_id,deployment_id,kind,requested_by,authorized_by,idempotency_key,payload_digest)
 SELECT a.id,a.issuer_binding_id,a.deployment_id,'issue','9d000000-0000-4000-8000-000000000001','9d000000-0000-4000-8000-000000000001',gen_random_uuid(),decode(repeat('88',32),'hex') FROM certichain_private.certificate_anchors a;
SELECT is(public.lookup_public_certificate_v2(c.credential_code,'local')->'anchor'->>'state','requested','Minimal pending projection') FROM public.certificates c WHERE c.id=(SELECT valid FROM ids);
INSERT INTO certichain_private.blockchain_issuers(id,deployment_id,institution_id,issuer_id,signer,desired_can_issue,desired_can_revoke)
 SELECT '9d000000-0000-4000-8000-000000000023',id,'9d000000-0000-4000-8000-000000000012',decode(repeat('99',32),'hex'),decode(repeat('66',20),'hex'),true,true FROM deployment;
CREATE TEMP TABLE cross_certificate AS SELECT pg_temp.published() id;
SELECT throws_ok(format($q$INSERT INTO certichain_private.certificate_anchors(certificate_id,issuance_operation_id,institution_id,deployment_id,issuer_binding_id,credential_code_snapshot,certificate_key,document_sha256,salt,commitment)
 SELECT c.id,c.issuance_operation_id,c.institution_id,d.id,'9d000000-0000-4000-8000-000000000023',c.credential_code::uuid,
 extensions.digest(uuid_send(c.credential_code::uuid),'sha256'),decode(c.document_hash,'hex'),decode(repeat('11',32),'hex'),decode(repeat('22',32),'hex') FROM public.certificates c CROSS JOIN deployment d WHERE c.id=%L$q$,(SELECT id FROM cross_certificate)),'23503',NULL,'Composite binding rejects another institution without client grants');
SELECT ok(NOT (public.lookup_public_certificate_v2(c.credential_code,'local')::text ~ '(salt|document_sha256|raw_signed_tx|nonce|operation_id|document_path|holder_id)'),'Public technical projection excludes private material') FROM public.certificates c WHERE c.id=(SELECT valid FROM ids);
SELECT is(public.authorize_certificate_opening((SELECT valid FROM ids),actor,'local') IS NOT NULL,allowed,'Opening policy: '||label) FROM (VALUES
 ('9d000000-0000-4000-8000-000000000001'::uuid,true,'owner'),('9d000000-0000-4000-8000-000000000002'::uuid,true,'holder'),
 ('9d000000-0000-4000-8000-000000000003'::uuid,false,'other holder'),('9d000000-0000-4000-8000-000000000004'::uuid,false,'platform without membership'),(NULL::uuid,false,'anonymous')) x(actor,allowed,label);
INSERT INTO certichain_private.blockchain_transaction_attempts(id,operation_id,deployment_id,attempt_number,signer,nonce,transaction_hash,calldata,calldata_digest,gas_limit,max_fee_per_gas,max_priority_fee_per_gas,authorized_by,state,receipt_status,block_number,block_hash,transaction_index,validated_log_index,observed_at,receipt_observations)
 SELECT '9d000000-0000-4000-8000-000000000033',o.id,o.deployment_id,0,decode(repeat('66',20),'hex'),0,decode(repeat('aa',32),'hex'),decode('f8362009','hex')||a.certificate_key||a.commitment||b.issuer_id,o.payload_digest,100000,1,1,o.authorized_by,'included',1,12,decode(repeat('bb',32),'hex'),0,0,'2026-10-13T00:00:00Z',
 '[{"status":1,"block_number":"12","block_hash":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","transaction_index":"0","validated_log_index":"0","observed_at":"2026-10-13T00:00:00Z","canonical":true}]'::jsonb
 FROM certichain_private.blockchain_operations o JOIN certichain_private.certificate_anchors a ON a.id=o.anchor_id JOIN certichain_private.blockchain_issuers b ON b.id=a.issuer_binding_id;
UPDATE certichain_private.blockchain_operations SET state='confirmed',canonical_attempt_id='9d000000-0000-4000-8000-000000000033',confirmations=1,finality='not_applicable',checked_at='2026-10-13T00:00:01Z' WHERE anchor_id IS NOT NULL;
UPDATE certichain_private.blockchain_operations SET state='blocked',last_error='rpc_unavailable' WHERE anchor_id IS NOT NULL;
SELECT is(public.lookup_public_certificate_v2(c.credential_code,'local')->'anchor'->'last_evidence'->>'state','confirmed','A technical blockage does not manufacture a reorg; confirmation is earlier receipt evidence') FROM public.certificates c WHERE c.id=(SELECT valid FROM ids);
SELECT is(public.lookup_public_certificate_v2(c.credential_code,'local')->'anchor'->'last_evidence'->>'checked_at','2026-10-13T00:00:01+00:00','Previous receipt date is not refreshed by the query or blockage') FROM public.certificates c WHERE c.id=(SELECT valid FROM ids);
SELECT is((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(public.authorize_certificate_opening((SELECT valid FROM ids),'9d000000-0000-4000-8000-000000000002','local')) k),ARRAY['chain_id','contract_address','credential_code','document_sha256','issuer_id','protocol_version','salt'],'Opening closed projection');
UPDATE certichain_private.blockchain_deployments SET enabled=false WHERE id=(SELECT id FROM deployment);
SELECT ok(public.authorize_certificate_opening((SELECT valid FROM ids),'9d000000-0000-4000-8000-000000000002','local') IS NOT NULL,'Disabled deployment retains original opening locator');
SELECT ok(public.lookup_public_certificate_v2(c.credential_code,'local')->'anchor' <> 'null'::jsonb,'Disabled deployment does not falsely erase an existing anchor') FROM public.certificates c WHERE c.id=(SELECT valid FROM ids);
UPDATE certichain_private.blockchain_deployments SET enabled=true WHERE id=(SELECT id FROM deployment);
SELECT set_config('request.jwt.claim.sub','9d000000-0000-4000-8000-000000000004',true);
UPDATE public.institutions SET verification_status='suspended' WHERE id='9d000000-0000-4000-8000-000000000011';
SELECT ok(public.authorize_certificate_opening((SELECT valid FROM ids),'9d000000-0000-4000-8000-000000000002','local') IS NOT NULL,'Holder retains opening under suspension');
SELECT ok(public.authorize_certificate_opening((SELECT valid FROM ids),'9d000000-0000-4000-8000-000000000001','local') IS NULL,'Suspended member denied');
SELECT ok(public.authorize_certificate_opening((SELECT incomplete FROM ids),'9d000000-0000-4000-8000-000000000002','local') IS NULL,'Incomplete publication denied');
SELECT ok(public.authorize_certificate_opening((SELECT valid FROM ids),'9d000000-0000-4000-8000-000000000002','other') IS NULL,'Cross deployment/environment denied');
SET LOCAL ROLE anon;
SELECT throws_ok($$SELECT public.lookup_public_certificate_v2('9d000000-0000-4000-8000-000000000099','local')$$,'42501',NULL,'Anon technical RPC denied');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT throws_ok($$SELECT public.authorize_certificate_opening('9d000000-0000-4000-8000-000000000099','9d000000-0000-4000-8000-000000000002','local')$$,'42501',NULL,'Opening client RPC denied');
SELECT throws_ok('SELECT salt FROM certichain_private.certificate_anchors','42501',NULL,'Private salt table denied');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
