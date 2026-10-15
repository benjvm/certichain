param([switch]$BackendOnly, [switch]$VisibleBrowser)
$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$target = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('certichain-8d-' + [guid]::NewGuid())))
$saved = @{}
foreach ($name in @('CERTICHAIN_TEST_CAMERA','CERTICHAIN_TEST_DISPOSABLE','CERTICHAIN_ANVIL_BIN','CERTICHAIN_SOURCE_ROOT','CERTICHAIN_9E_VISIBLE_BROWSER','SUPABASE_CLI')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
function Stage([string]$Name, [scriptblock]$Action) {
  Write-Output "10 stage: $Name"
  & $Action
  if ($LASTEXITCODE -ne 0) { throw "10 stage failed: $Name" }
}
Push-Location -LiteralPath $source
try {
  $env:CERTICHAIN_TEST_CAMERA = '0'
  $env:CERTICHAIN_TEST_DISPOSABLE = '1'
  $env:CERTICHAIN_SOURCE_ROOT = $source
  $env:CERTICHAIN_9E_VISIBLE_BROWSER = if ($VisibleBrowser) { '1' } else { '0' }
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
  $mode = @(); if ($BackendOnly) { $mode = @('--backend-only') }
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
} finally {
  try {
    if (Test-Path -LiteralPath (Join-Path $target 'supabase/config.toml')) {
      & ./supabase/tests/stop_disposable_local.ps1 -Root $target
      $summaryPath = Join-Path $source 'mobile/build/phase10-evidence/result.json'
      if (Test-Path -LiteralPath $summaryPath) {
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $summary | Add-Member -NotePropertyName stack_cleanup -NotePropertyValue 'PASS' -Force
        $summary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $summaryPath -Encoding utf8
        $modePath = Join-Path $source ('mobile/build/phase10-evidence/' + $(if ($BackendOnly) { 'backend-only.json' } else { 'full.json' }))
        if (Test-Path -LiteralPath $modePath) { $summary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $modePath -Encoding utf8 }
      }
    }
  } finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
    Pop-Location
  }
}
