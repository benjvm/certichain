# Extra local preservation check. Rebuilds the historical certificate permissions
# inside a rollback-only transaction, then applies the new migration with data.
# From the repository root, use powershell -NoProfile -ExecutionPolicy Bypass
# -File supabase/tests/verify_certificate_migration.ps1 (process policy only).
param([string]$DatabaseContainer = 'supabase_db_certichain')
$ErrorActionPreference = 'Stop'

$phase5Repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$phase5Tests = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'certificate_authorization.test.sql')
$phase5FixtureMatch = [regex]::Match($phase5Tests, '(?s)-- Synthetic fixtures begin\.(.*?)-- Synthetic fixtures end\.')
if (-not $phase5FixtureMatch.Success) { throw 'Synthetic SQL fixtures were not found.' }
$phase5Historical = Get-Content -Raw -LiteralPath (Join-Path $phase5Repo 'supabase/migrations/20260918194306_rls_policies.sql')
$phase5PolicyStart = $phase5Historical.IndexOf('CREATE POLICY certificates_insert_authorized')
if ($phase5PolicyStart -lt 0) { throw 'Historical certificate policies were not found.' }
$phase5Migration = Get-Content -Raw -LiteralPath (Join-Path $phase5Repo 'supabase/migrations/20260928202802_close_direct_certificate_writes.sql')

$phase5Sql = @'
BEGIN;
SET LOCAL search_path = public, extensions;

'@ + $phase5FixtureMatch.Groups[1].Value + @'
-- Restore the precise historical policies/grants for this transaction only.
GRANT ALL PRIVILEGES ON public.certificates TO anon, authenticated;
GRANT TRUNCATE, REFERENCES, TRIGGER ON public.profiles, public.institutions, public.institution_members TO anon, authenticated;
GRANT EXECUTE ON FUNCTION certichain_private.protect_certificate_update() TO authenticated;

'@ + $phase5Historical.Substring($phase5PolicyStart) + "`n" + $phase5Migration + @'

DO $$
DECLARE
    snapshot record;
    actual_rows jsonb;
BEGIN
    FOR snapshot IN SELECT table_name, rows FROM phase5_snapshot LOOP
        EXECUTE format('SELECT jsonb_agg(to_jsonb(t) ORDER BY id) FROM public.%I AS t', snapshot.table_name)
            INTO actual_rows;
        IF actual_rows IS DISTINCT FROM snapshot.rows THEN
            RAISE EXCEPTION 'Migration changed existing rows in %', snapshot.table_name;
        END IF;
    END LOOP;
    IF has_table_privilege('authenticated', 'public.certificates', 'INSERT,UPDATE,DELETE,TRUNCATE')
       OR EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'public.certificates'::regclass AND polcmd <> 'r') THEN
        RAISE EXCEPTION 'Certificate writes remain authorized';
    END IF;
END;
$$;
SELECT 'PASS: migration applied over historical permissions with 6 synthetic certificates; all four tables preserved exactly';
ROLLBACK;
'@

$phase5Sql | docker exec -i $DatabaseContainer psql -X -q -A -t -U postgres -d postgres -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw 'Local certificate migration preservation check failed.' }
