param([Parameter(Mandatory=$true)][string]$DatabaseContainer)
$ErrorActionPreference='Stop'
if ($DatabaseContainer -notmatch '^supabase_db_certichain_8[ad]_[0-9a-f]{8}$' -and !($env:GITHUB_ACTIONS -eq 'true' -and $DatabaseContainer -eq 'supabase_db_certichain')) { throw 'Owned disposable database required.' }
$migrationA=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../migrations/20261015100000_irreversible_revocation.sql'))
$migrationB=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../migrations/20261015110000_revocation_public_v3.sql'))
$migrationC=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../migrations/20261016110000_revocation_reauthorization_unavailable.sql'))
# Reconstruct only the pre-10 additions in a rollback-only transaction. All old
# issuance/institution/document guards remain enabled. No application data is deleted.
$setup=@'
BEGIN;
DROP FUNCTION public.request_certificate_revocation(uuid,uuid,uuid,text);
DROP FUNCTION public.certificate_revocation_progress(uuid,uuid);
DROP FUNCTION public.reauthorize_certificate_revocation(uuid,uuid);
DROP FUNCTION public.lookup_public_certificate_v3(text,text);
DROP TABLE certichain_private.certificate_revocation_keys;
DROP TABLE certichain_private.certificate_revocations;
DROP TRIGGER certificates_00_revocation_guard ON public.certificates;
DROP FUNCTION certichain_private.protect_revoked_certificate();
DROP FUNCTION certichain_private.authorize_revocation(uuid,uuid);
DROP FUNCTION certichain_private.revocation_immutable();
ALTER TABLE public.certificates DROP CONSTRAINT revocation_certificate_institution;
INSERT INTO auth.users(id,raw_user_meta_data,email_confirmed_at) VALUES
('aa100000-0000-4000-8000-000000000001','{"full_name":"Synthetic owner"}',now()),
('aa100000-0000-4000-8000-000000000002','{"full_name":"Synthetic holder"}',now());
INSERT INTO public.institutions(id,name,slug,verification_status) VALUES
('aa100000-0000-4000-8000-000000000011','Synthetic historical institution','phase10-preservation','verified');
INSERT INTO public.institution_members(institution_id,user_id,role) VALUES
('aa100000-0000-4000-8000-000000000011','aa100000-0000-4000-8000-000000000001','owner');
INSERT INTO public.certificates(id,institution_id,issued_by,holder_id,title,credential_code,document_hash,status,revoked_at) VALUES
('aa100000-0000-4000-8000-000000000021','aa100000-0000-4000-8000-000000000011','aa100000-0000-4000-8000-000000000001','aa100000-0000-4000-8000-000000000002','Legacy active','OLD-CODE','UNKNOWN','active',NULL),
('aa100000-0000-4000-8000-000000000022','aa100000-0000-4000-8000-000000000011','aa100000-0000-4000-8000-000000000001','aa100000-0000-4000-8000-000000000002','Legacy revoked','AA100000-0000-4000-8000-000000000099',NULL,'revoked','2020-01-01T00:00:00.123456Z');
CREATE TEMP TABLE phase10_preserved AS SELECT to_jsonb(c) AS row FROM public.certificates c;
CREATE TEMP TABLE phase10_publication AS SELECT to_jsonb(o) AS row FROM public.certificate_issuance_operations o;
CREATE TEMP TABLE phase10_anchors AS SELECT to_jsonb(a) AS row FROM certichain_private.certificate_anchors a;
'@
$assert=@'
DO $$ BEGIN
  IF EXISTS((SELECT row FROM phase10_preserved) EXCEPT ALL (SELECT to_jsonb(c) FROM public.certificates c))
    OR EXISTS((SELECT to_jsonb(c) FROM public.certificates c) EXCEPT ALL (SELECT row FROM phase10_preserved))
    OR EXISTS((SELECT row FROM phase10_publication) EXCEPT ALL (SELECT to_jsonb(o) FROM public.certificate_issuance_operations o))
    OR EXISTS((SELECT row FROM phase10_anchors) EXCEPT ALL (SELECT to_jsonb(a) FROM certichain_private.certificate_anchors a)) THEN
    RAISE EXCEPTION 'Migration changed historical data';
  END IF;
  IF EXISTS(SELECT 1 FROM certichain_private.certificate_revocations) OR EXISTS(SELECT 1 FROM certichain_private.certificate_revocation_keys) THEN
    RAISE EXCEPTION 'Historical audit was invented';
  END IF;
  IF public.lookup_public_certificate('aa100000-0000-4000-8000-000000000099')->>'result'<>'not_found' THEN
    RAISE EXCEPTION 'Legacy eligibility widened';
  END IF;
  PERFORM public.request_certificate_revocation('aa100000-0000-4000-8000-000000000001','aa100000-0000-4000-8000-000000000022',gen_random_uuid(),'No invented reason');
  IF EXISTS(SELECT 1 FROM certichain_private.certificate_revocations)
    OR (SELECT revoked_at FROM public.certificates WHERE id='aa100000-0000-4000-8000-000000000022')<>'2020-01-01T00:00:00.123456Z'::timestamptz THEN
    RAISE EXCEPTION 'Historical revocation overwritten';
  END IF;
END $$;
ROLLBACK;
'@
$sql=$setup+"`n"+$migrationA+"`n"+$migrationB+"`n"+$migrationC+"`n"+$assert
$output=$sql | docker exec -i $DatabaseContainer psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1
if($LASTEXITCODE -ne 0){throw 'Phase10 rollback-only migration preservation failed; no private SQL detail emitted.'}
Write-Output 'PASS phase10 migrations preserve historical active/revoked/publication/anchor rows and do not invent audit or eligibility'
