param([switch]$Full)
$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$target = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('certichain-8d-' + [guid]::NewGuid())))
$saved = @{}
foreach ($name in @('CERTICHAIN_TEST_DISPOSABLE','CERTICHAIN_TEST_BACKEND_ROOT','CERTICHAIN_RELEASE_SKIP_BUILD')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
function Stage([string]$Name, [scriptblock]$Action) {
    Write-Output "8D stage: $Name"
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "8D stage failed: $Name (exit $LASTEXITCODE)" }
}
Push-Location -LiteralPath $source
try {
    if ((node --version) -ne 'v24.14.0') { throw 'Use Node 24.14.0 from .node-version.' }
    $null = & "$PSScriptRoot/prepare_disposable_local.ps1" -Destination $target -Start
    $env:CERTICHAIN_TEST_DISPOSABLE = '1'
    $env:CERTICHAIN_TEST_BACKEND_ROOT = $target
    Remove-Item Env:CERTICHAIN_RELEASE_SKIP_BUILD -ErrorAction SilentlyContinue
    if ($Full) {
        Stage 'SQL' { & $env:SUPABASE_CLI test db --local --workdir $target }
        Stage 'SQL lint' { & $env:SUPABASE_CLI db lint --local --workdir $target --schema public,certichain_private --level warning --fail-on warning }
        Push-Location -LiteralPath $target
        try {
            foreach ($suite in @('issuance_http','issuance_hardening','private_storage','certificate_pdf_http','public_verification_http','hash_comparison_http','institution_concurrency')) {
                Stage $suite { node "supabase/tests/$suite.mjs" }
            }
            foreach ($suite in @('verify_certificate_migration','verify_private_issuance_migration','verify_public_verification_migration','verify_hash_comparison_migration')) {
                Stage $suite { & "./supabase/tests/$suite.ps1" }
            }
        } finally { Pop-Location }
        Stage 'Deno format' { npx --yes deno@2.2.12 fmt --check supabase/functions }
        Stage 'Deno lint' { npx --yes deno@2.2.12 lint supabase/functions }
        Stage 'Deno types' { npx --yes deno@2.2.12 check --frozen --config supabase/functions/deno.json supabase/functions/issue-certificate/index.ts supabase/functions/certificate-pdf/index.ts supabase/functions/verify-certificate/index.ts supabase/functions/compare-certificate-hash/index.ts }
        Stage 'Deno tests' { npx --yes deno@2.2.12 test --frozen --config supabase/functions/deno.json supabase/functions }
        Stage 'CDP and readiness' { node --test mobile/tool/browser_harness_test.mjs supabase/tests/edge_runtime_test.mjs }
    }
    Push-Location mobile/tool
    try {
        Stage 'Frozen decoder dependencies' { npm ci --ignore-scripts }
        Stage 'Decoder regeneration' { node prepare_decoder.mjs }
        Stage 'Decoder drift' { node prepare_decoder.mjs --check }
        Stage 'Versioned decoder' { git diff --exit-code -- ../web/decoder }
    } finally { Pop-Location }
    Push-Location mobile
    try {
        Stage 'Frozen Flutter dependencies' { flutter pub get --enforce-lockfile }
        if ($Full) {
            Stage 'Dart format' { dart format --output=none --set-exit-if-changed lib test tool }
            Stage 'Flutter analyze' { flutter analyze }
            Stage 'Flutter tests' { flutter test }
            Stage '7D build' { flutter build web --no-web-resources-cdn --target=tool/secure_issuance_browser.dart --output=build/secure-issuance-e2e }
            Stage '7D complementary journey' { node tool/secure_issuance_browser.mjs }
            Stage '8B+8C build' { flutter build web --no-web-resources-cdn --target=tool/public_verification_browser.dart --output=build/public-verification-e2e }
            Stage '8B+8C startup-error build' { flutter build web --debug --no-web-resources-cdn --base-href=/production/ --dart-define=SUPABASE_URL=http://127.0.0.1:55321 --dart-define=PUBLIC_VERIFICATION_BASE_URL=http://127.0.0.1:7357/production/ --output=build/public-verification-main }
            Stage '8B+8C complementary journey' { node tool/public_verification_browser.mjs }
            Stage 'PDF adapter build' { flutter build web --no-web-resources-cdn --target=tool/pdf_browser_smoke.dart --output=build/browser-smoke }
            Stage 'PDF adapters' { node tool/pdf_browser_smoke.mjs }
        }
        Stage 'Production release HTTPS journey' { node tool/release_verification_browser.mjs }
    } finally { Pop-Location }
} finally {
    try {
        if ((Test-Path -LiteralPath (Join-Path $target 'supabase/config.toml')) -and $env:SUPABASE_CLI) {
            $null = & $env:SUPABASE_CLI stop --no-backup --workdir $target 2>&1
            if ($LASTEXITCODE -ne 0) { throw 'Own disposable stack did not stop; preserve it for inspection.' }
        }
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
        if (!$target.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($target) -notmatch '^certichain-8d-[0-9a-f-]{36}$') { throw 'Unsafe disposable cleanup target.' }
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    } finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
        Pop-Location
    }
}
