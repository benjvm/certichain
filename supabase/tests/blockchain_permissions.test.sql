BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET LOCAL search_path=public,extensions;
SELECT no_plan();
SELECT ok(c.relrowsecurity,'RLS: '||c.relname) FROM pg_class c JOIN pg_namespace n ON c.relnamespace=n.oid
  WHERE n.nspname='certichain_private' AND c.relname IN ('blockchain_deployments','blockchain_issuers','certificate_anchors','blockchain_operations','blockchain_transaction_attempts','blockchain_signer_nonces');
SELECT ok(NOT has_table_privilege(r.role_name,c.oid,p.priv),'No '||p.priv||' for '||r.role_name||' on '||c.relname)
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace=n.oid
  CROSS JOIN (VALUES('anon'),('authenticated'),('service_role')) r(role_name)
  CROSS JOIN (VALUES('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER')) p(priv)
  WHERE n.nspname='certichain_private' AND c.relname IN ('blockchain_deployments','blockchain_issuers','certificate_anchors','blockchain_operations','blockchain_transaction_attempts','blockchain_signer_nonces');
SELECT unnest(ARRAY[ok(p.prosecdef,'SECURITY DEFINER: '||p.proname),ok(p.proconfig @> ARRAY['search_path=""'],'Empty search_path: '||p.proname),
  ok(has_function_privilege('service_role',p.oid,'EXECUTE'),'Service EXECUTE: '||p.proname),
  ok(NOT has_function_privilege('anon',p.oid,'EXECUTE'),'Anon denied: '||p.proname),
  ok(NOT has_function_privilege('authenticated',p.oid,'EXECUTE'),'Authenticated denied: '||p.proname)])
  FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='public' AND p.proname LIKE 'blockchain_%';
SET LOCAL ROLE anon;
SELECT throws_ok('SELECT salt FROM certichain_private.certificate_anchors','42501',NULL,'Anon cannot read salt with a known UUID');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT throws_ok('SELECT raw_signed_tx FROM certichain_private.blockchain_transaction_attempts','42501',NULL,'Authenticated cannot read signed capability');
SELECT throws_ok('SELECT public.blockchain_queue()','42501',NULL,'Authenticated cannot invoke worker queue');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT throws_ok('SELECT next_nonce FROM certichain_private.blockchain_signer_nonces','42501',NULL,'Service role cannot SELECT nonce tables directly');
SELECT lives_ok('SELECT public.blockchain_queue()','Service role uses narrow RPC');
RESET ROLE;
SELECT is((SELECT count(*) FROM pg_constraint WHERE conname IN ('anchor_certificate_identity','anchor_publication_identity','blockchain_canonical_attempt_fk')),3::bigint,'Composite parent/canonical constraints installed');
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='certichain_private' AND tablename LIKE 'blockchain_%'),'No client RLS policies');
SELECT * FROM finish();
ROLLBACK;
