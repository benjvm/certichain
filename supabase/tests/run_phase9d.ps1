param([switch]$BackendOnly)
$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$target=$null
$saved=@{}
foreach($name in @('CERTICHAIN_TEST_CAMERA','CERTICHAIN_TEST_DISPOSABLE','CERTICHAIN_ANVIL_BIN','CERTICHAIN_SOURCE_ROOT','CERTICHAIN_9D_BROWSER','SUPABASE_CLI')) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
Push-Location -LiteralPath $source
try {
  $env:CERTICHAIN_TEST_CAMERA='0'
  $env:CERTICHAIN_TEST_DISPOSABLE='1'
  $env:CERTICHAIN_9D_BROWSER=if($BackendOnly){'0'}else{'1'}
  $env:CERTICHAIN_SOURCE_ROOT=$source
  node blockchain/scripts/anvil-linux.mjs
  if($LASTEXITCODE -ne 0) { throw 'Frozen Anvil preparation failed' }
  $env:CERTICHAIN_ANVIL_BIN=Join-Path $source 'blockchain/.tools/anvil-linux/anvil'
  if(!$env:SUPABASE_CLI) {
    $env:SUPABASE_CLI=node -p "require('node:path').join(require('node:path').dirname(require.resolve('@supabase/cli-windows-x64/package.json')),'bin','supabase.exe')"
    if($LASTEXITCODE -ne 0) { throw 'Pinned CLI unavailable' }
  }
  $target=& ./supabase/tests/prepare_disposable_local.ps1 -Start
  & $env:SUPABASE_CLI test db --local --workdir $target
  if($LASTEXITCODE -ne 0) { throw 'SQL tests failed' }
  & $env:SUPABASE_CLI db lint --local --workdir $target --schema public,certichain_private --level warning --fail-on warning
  if($LASTEXITCODE -ne 0) { throw 'SQL lint failed' }
  Push-Location -LiteralPath $target
  try {
    npx --yes deno@2.2.12 run --allow-all --frozen --config supabase/functions/deno.json supabase/tests/blockchain_verification_integration.ts
    if($LASTEXITCODE -ne 0) { throw '9D real integration failed' }
  }finally{Pop-Location}
}finally{
  if($target){& ./supabase/tests/stop_disposable_local.ps1 -Root $target}
  foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
  Pop-Location
}
