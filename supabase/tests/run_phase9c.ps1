$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$target=$null
$saved=@{}
foreach($name in @('CERTICHAIN_TEST_CAMERA','CERTICHAIN_TEST_DISPOSABLE','CERTICHAIN_ANVIL_BIN','CERTICHAIN_SOURCE_ROOT','SUPABASE_CLI')) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
Push-Location -LiteralPath $source
try {
  $env:CERTICHAIN_TEST_CAMERA='0'
  $env:CERTICHAIN_TEST_DISPOSABLE='1'
  node blockchain/scripts/anvil-linux.mjs
  if($LASTEXITCODE -ne 0) { throw 'Frozen Linux Anvil preparation failed' }
  $env:CERTICHAIN_ANVIL_BIN=Join-Path $source 'blockchain/.tools/anvil-linux/anvil'
  $env:CERTICHAIN_SOURCE_ROOT=$source
  if(!$env:SUPABASE_CLI) {
    $env:SUPABASE_CLI = node -p "require('node:path').join(require('node:path').dirname(require.resolve('@supabase/cli-windows-x64/package.json')),'bin','supabase.exe')"
    if($LASTEXITCODE -ne 0) { throw 'Pinned Supabase CLI unavailable' }
  }
  if((& $env:SUPABASE_CLI --version 2>$null) -ne '2.117.0') { throw 'Expected Supabase CLI 2.117.0' }
  $target=& ./supabase/tests/prepare_disposable_local.ps1
  $null = & $env:SUPABASE_CLI start --workdir $target 2>&1
  if($LASTEXITCODE -ne 0) { throw 'Owned Supabase startup failed' }
  New-Item -ItemType Directory -Path (Join-Path $target 'blockchain/out/CertificateRegistry.sol') -Force | Out-Null
  Copy-Item blockchain/out/CertificateRegistry.sol/CertificateRegistry.json (Join-Path $target 'blockchain/out/CertificateRegistry.sol/')
  Copy-Item blockchain/artifacts (Join-Path $target 'blockchain/') -Recurse
  Copy-Item blockchain/fixtures (Join-Path $target 'blockchain/') -Recurse
  Push-Location -LiteralPath $target
  try {
    & $env:SUPABASE_CLI test db --local
    if($LASTEXITCODE -ne 0) { throw 'SQL tests failed' }
    & $env:SUPABASE_CLI db lint --local --schema public,certichain_private --level warning --fail-on warning
    if($LASTEXITCODE -ne 0) { throw 'SQL lint failed' }
    npx --yes deno@2.2.12 run --allow-all --frozen --config supabase/functions/deno.json supabase/tests/blockchain_integration.ts
    if($LASTEXITCODE -ne 0) { throw 'Real 9C integration failed' }
  } finally { Pop-Location }
} finally {
  if($target) { & ./supabase/tests/stop_disposable_local.ps1 -Root $target }
  foreach($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
  Pop-Location
}
