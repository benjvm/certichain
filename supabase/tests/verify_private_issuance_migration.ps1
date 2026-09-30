# Reapply 7A inside a rollback-only transaction over historical synthetic rows.
param([string]$DatabaseContainer = 'supabase_db_certichain')
$ErrorActionPreference = 'Stop'
$migration = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../migrations/20260930120000_prepare_private_issuance.sql')
$sql = @'
BEGIN;
-- Rewind only 7A inside this transaction; the final ROLLBACK restores it.
DROP POLICY certificates_objects_no_client_select ON storage.objects;
DROP POLICY certificates_objects_no_client_insert ON storage.objects;
DROP POLICY certificates_objects_no_client_update ON storage.objects;
DROP POLICY certificates_objects_no_client_delete ON storage.objects;
DROP TRIGGER certificates_issued_protect_update ON public.certificates;
DROP TRIGGER issuance_operation_protect_update ON public.certificate_issuance_operations;
DROP FUNCTION certichain_private.protect_issued_certificate_update();
DROP FUNCTION certichain_private.protect_issuance_operation_update();
DROP TABLE public.certificate_issuance_operations CASCADE;
ALTER TABLE public.certificates DROP COLUMN issuance_operation_id CASCADE;

INSERT INTO auth.users (id, raw_user_meta_data) VALUES
('7b000000-0000-4000-8000-000000000001', '{"full_name":"Synthetic Issuer"}'),
('7b000000-0000-4000-8000-000000000002', '{"full_name":"Synthetic Holder"}');
INSERT INTO public.institutions (id, name, slug) VALUES
('7b000000-0000-4000-8000-000000000011', 'Synthetic History', 'phase7a-history');
INSERT INTO public.institution_members (institution_id, user_id, role) VALUES
('7b000000-0000-4000-8000-000000000011', '7b000000-0000-4000-8000-000000000001', 'owner');
INSERT INTO public.certificates
(id, holder_id, institution_id, issued_by, title, credential_code, document_path, document_hash)
VALUES
('7b000000-0000-4000-8000-000000000021', '7b000000-0000-4000-8000-000000000002',
 '7b000000-0000-4000-8000-000000000011', '7b000000-0000-4000-8000-000000000001',
 'No PDF', 'phase7a-no-pdf', NULL, NULL),
('7b000000-0000-4000-8000-000000000022', '7b000000-0000-4000-8000-000000000002',
 '7b000000-0000-4000-8000-000000000011', '7b000000-0000-4000-8000-000000000001',
 'Unknown format', 'phase7a-old-hash', 'old/path', 'NOT-A-SHA256');
CREATE TEMP TABLE historical_snapshot AS
SELECT id, to_jsonb(c) AS row_before FROM public.certificates AS c
WHERE id IN ('7b000000-0000-4000-8000-000000000021',
             '7b000000-0000-4000-8000-000000000022');
'@ + "`n" + $migration + @'

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM historical_snapshot AS s
      JOIN public.certificates AS c USING (id)
      WHERE to_jsonb(c) - 'issuance_operation_id' IS DISTINCT FROM s.row_before
         OR c.issuance_operation_id IS NOT NULL)
     OR (SELECT count(*) FROM historical_snapshot) <> 2 THEN
    RAISE EXCEPTION '7A modified historical certificates';
  END IF;
END;
$$;
UPDATE public.certificates SET status = 'revoked'
WHERE credential_code IN ('phase7a-no-pdf', 'phase7a-old-hash');
DO $$
BEGIN
  IF (SELECT count(*) FROM public.certificates WHERE status = 'revoked'
      AND credential_code IN ('phase7a-no-pdf', 'phase7a-old-hash')) <> 2 THEN
    RAISE EXCEPTION 'Historical revocation failed after 7A';
  END IF;
END;
$$;
SELECT 'PASS: 7A migration preserves old NULL/unknown document formats and allows later revocation';
ROLLBACK;
'@
$sql | docker exec -i $DatabaseContainer psql -X -q -A -t -U postgres -d postgres -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw 'Local 7A historical migration check failed.' }
