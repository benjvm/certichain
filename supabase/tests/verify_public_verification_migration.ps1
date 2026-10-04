param([string]$DatabaseContainer = 'supabase_db_certichain')
$ErrorActionPreference = 'Stop'
if ($DatabaseContainer -notmatch '^supabase_db_[a-zA-Z0-9_-]+$') { throw 'Local Supabase container required.' }
$migration = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../migrations/20261004173032_public_certificate_verification.sql')
$sql = @'
BEGIN;
DROP FUNCTION public.lookup_public_certificate(text);
DROP FUNCTION public.consume_public_verification_budget();
DROP FUNCTION certichain_private.public_verification_result(boolean,timestamptz,boolean,timestamptz);
DROP TABLE certichain_private.public_verification_budget;
INSERT INTO auth.users(id,raw_user_meta_data) VALUES
('8a100000-0000-4000-8000-000000000001','{"full_name":"Synthetic Issuer"}'),
('8a100000-0000-4000-8000-000000000002','{"full_name":"Synthetic Holder"}');
INSERT INTO public.institutions(id,name,slug) VALUES('8a100000-0000-4000-8000-000000000011','Historical Institution','phase8a-history');
INSERT INTO public.institution_members(institution_id,user_id,role) VALUES
('8a100000-0000-4000-8000-000000000011','8a100000-0000-4000-8000-000000000001','owner');
INSERT INTO public.certificates(institution_id,holder_id,issued_by,title,credential_code,document_path,document_hash) VALUES
('8a100000-0000-4000-8000-000000000011','8a100000-0000-4000-8000-000000000002','8a100000-0000-4000-8000-000000000001','Old Format','OLD-CODE','old/document.pdf','UNKNOWN'),
('8a100000-0000-4000-8000-000000000011','8a100000-0000-4000-8000-000000000002','8a100000-0000-4000-8000-000000000001','Old UUID','8A100000-0000-4000-8000-000000000099',NULL,NULL);
CREATE TEMP TABLE preserved AS
 SELECT 'certificates' AS source,to_jsonb(c) AS row FROM public.certificates c
 UNION ALL SELECT 'operations',to_jsonb(o) FROM public.certificate_issuance_operations o
 UNION ALL SELECT 'institutions',to_jsonb(i) FROM public.institutions i
 UNION ALL SELECT 'profiles',to_jsonb(p) FROM public.profiles p
 UNION ALL SELECT 'members',to_jsonb(m) FROM public.institution_members m
 UNION ALL SELECT 'objects',to_jsonb(o) FROM storage.objects o;
'@ + "`n" + $migration + @'

DO $$
BEGIN
 IF EXISTS((SELECT source,row FROM preserved) EXCEPT ALL (
 SELECT 'certificates',to_jsonb(c) FROM public.certificates c
 UNION ALL SELECT 'operations',to_jsonb(o) FROM public.certificate_issuance_operations o
 UNION ALL SELECT 'institutions',to_jsonb(i) FROM public.institutions i
 UNION ALL SELECT 'profiles',to_jsonb(p) FROM public.profiles p
 UNION ALL SELECT 'members',to_jsonb(m) FROM public.institution_members m
 UNION ALL SELECT 'objects',to_jsonb(o) FROM storage.objects o)) THEN
 RAISE EXCEPTION '8A modified existing data'; END IF;
 IF public.lookup_public_certificate('8a100000-0000-4000-8000-000000000099') <>
 '{"schema_version":"1","result":"not_found"}'::jsonb THEN
 RAISE EXCEPTION 'Legacy evidence was invented'; END IF;
END;
$$;
SELECT 'PASS: 8A migration preserves all private rows, codes and Storage metadata';
ROLLBACK;
'@
$sql | docker exec -i $DatabaseContainer psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw 'Public verification historical preservation failed.' }
