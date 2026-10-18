param([switch]$BackendOnly, [switch]$VisibleBrowser)
$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$target = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('certichain-8d-' + [guid]::NewGuid())))
$saved = @{}
foreach ($name in @('CERTICHAIN_ACCEPTANCE_RUN_ID','CERTICHAIN_TEST_CAMERA','CERTICHAIN_TEST_DISPOSABLE','CERTICHAIN_ANVIL_BIN','CERTICHAIN_SOURCE_ROOT','CERTICHAIN_9E_VISIBLE_BROWSER','SUPABASE_CLI')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
$completed = $false
$cleanup = 'NOT_RUN'
$runId = $null
function Stage([string]$Name, [scriptblock]$Action) {
  Write-Output "10 stage: $Name"
  & node (Join-Path $source 'supabase/tests/phase10_evidence.mjs') stage $Name
  if ($LASTEXITCODE -ne 0) { throw 'Cannot record current acceptance stage.' }
  & $Action
  if ($LASTEXITCODE -ne 0) { throw "10 stage failed: $Name" }
}
Push-Location -LiteralPath $source
try {
  $env:CERTICHAIN_TEST_CAMERA = '0'
  $env:CERTICHAIN_TEST_DISPOSABLE = '1'
  $env:CERTICHAIN_SOURCE_ROOT = $source
  $env:CERTICHAIN_9E_VISIBLE_BROWSER = if ($VisibleBrowser) { '1' } else { '0' }
  $mode = @(); if ($BackendOnly) { $mode = @('--backend-only') }
  $runId = & node supabase/tests/phase10_evidence.mjs begin @mode
  if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize acceptance evidence.' }
  $env:CERTICHAIN_ACCEPTANCE_RUN_ID = $runId
  if ((node --version) -ne 'v24.14.0') { throw 'Use Node 24.14.0 from .node-version.' }
  if (!$env:SUPABASE_CLI) {
    $resolver = @'
const path = require("node:path");
const suffix = process.platform === "win32" ? "windows" : process.platform === "darwin" ? "darwin" : "linux";
console.log(path.join(path.dirname(require.resolve("@supabase/cli-" + suffix + "-" + process.arch + "/package.json")), "bin", "supabase" + (process.platform === "win32" ? ".exe" : "")));
'@
    $command = Get-Command supabase -ErrorAction SilentlyContinue
    if ($command) { $env:SUPABASE_CLI = $command.Source }
    else { $env:SUPABASE_CLI = $resolver | node --input-type=commonjs; if ($LASTEXITCODE -ne 0) { throw 'Pinned Supabase CLI unavailable.' } }
  }
  Stage 'Frozen Foundry bootstrap' { node blockchain/scripts/bootstrap.mjs }
  Stage 'Toolchain preflight' { node supabase/tests/phase9e_preflight.mjs --phase10 @mode }
  if (!$BackendOnly) {
    Push-Location mobile
    try {
      Stage 'Frozen Flutter dependencies' { flutter pub get --enforce-lockfile }
      Push-Location tool
      try {
        Stage 'Frozen browser tools' { npm ci --ignore-scripts }
        Stage 'Offline decoder' { node prepare_decoder.mjs --check }
      } finally { Pop-Location }
    } finally { Pop-Location }
  }
  Stage 'Normal contract build' { node blockchain/scripts/forge.mjs build --force }
  Stage 'Contract artifacts' { node blockchain/scripts/artifacts.mjs --check }
  Stage 'Backend ABI' { node blockchain/scripts/backend-abi.mjs --check }
  if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    Stage 'Frozen Linux Anvil' { node blockchain/scripts/anvil-linux.mjs }
    $env:CERTICHAIN_ANVIL_BIN = Join-Path $source 'blockchain/.tools/anvil-linux/anvil'
  } else { $env:CERTICHAIN_ANVIL_BIN = Join-Path $source 'blockchain/.tools/bin/anvil' }
  $null = & ./supabase/tests/prepare_disposable_local.ps1 -Destination $target -Start
  Stage 'SQL permissions' { & $env:SUPABASE_CLI test db --local --workdir $target }
  $taskConfig=[IO.File]::ReadAllText((Join-Path $target 'supabase/config.toml'))
  $taskProject=[regex]::Match($taskConfig,'project_id = "([^"]+)"').Groups[1].Value
  Stage 'Historical migration preservation' { & ./supabase/tests/verify_revocation_migration.ps1 -DatabaseContainer ('supabase_db_'+$taskProject) }
  Stage 'SQL lint' { & $env:SUPABASE_CLI db lint --local --workdir $target --schema public,certichain_private --level warning --fail-on warning }
  Push-Location -LiteralPath $target
  try {
    Stage 'Real acceptance' { npx --yes deno@2.2.12 run --allow-all --frozen --config supabase/functions/deno.json supabase/tests/phase10_acceptance.ts @mode }
  } finally { Pop-Location }
  $completed = $true
} finally {
  try {
    if (Test-Path -LiteralPath (Join-Path $target 'supabase/config.toml')) {
      & ./supabase/tests/stop_disposable_local.ps1 -Root $target
      $cleanup = 'PASS'
    }
  } catch {
    $cleanup = 'FAIL'
    throw
  } finally {
    try {
      if ($runId) {
        & node (Join-Path $source 'supabase/tests/phase10_evidence.mjs') finish $(if ($completed) { '0' } else { '1' }) $cleanup
        if ($LASTEXITCODE -ne 0 -and $completed) { throw 'Acceptance or owned cleanup did not pass.' }
      }
    } finally {
      foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
      Pop-Location
    }
  }
}
