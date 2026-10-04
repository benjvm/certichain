# Copy only versioned backend sources. Never copy .temp, .branches, credentials or user data.
param([string]$Destination = (Join-Path $env:TEMP ('certichain-8a-' + [guid]::NewGuid())), [switch]$Start)
$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$target = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $target) { throw 'Disposable destination must not exist.' }
if ($target.StartsWith($source + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Disposable destination must be outside the repository.'
}
$project = 'certichain_8a_' + [guid]::NewGuid().ToString('N').Substring(0,8)
New-Item -ItemType Directory -Path (Join-Path $target 'supabase') -Force | Out-Null
Push-Location -LiteralPath $source
try {
    $files = git ls-files --cached --others --exclude-standard -- supabase/migrations supabase/functions supabase/tests supabase/scripts supabase/admin
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inventory backend sources.' }
    foreach ($file in $files) {
        if ([IO.Path]::GetFileName($file) -like '.env*') { continue }
        $output = Join-Path $target $file
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($output)) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $source $file) -Destination $output
    }
} finally { Pop-Location }
$config = [IO.File]::ReadAllText((Join-Path $source 'supabase/config.toml')).Replace('project_id = "certichain"', "project_id = `"$project`"")
foreach ($port in @(54320,54321,54322,54323,54324,54327,54329,8083)) {
    $config = $config.Replace("port = $port", "port = $($port + 1000)")
}
[IO.File]::WriteAllText((Join-Path $target 'supabase/config.toml'), $config)
# Only copied test/operator harnesses change their local container/loopback binding.
# Production function sources and migrations are copied byte-for-byte.
Get-ChildItem -LiteralPath (Join-Path $target 'supabase') -Recurse -File |
    Where-Object { $_.Extension -in @('.mjs','.ps1') } | ForEach-Object {
        $data = [IO.File]::ReadAllText($_.FullName).Replace('_certichain"', "_$project`"").Replace("_certichain'", "_$project'").Replace('54321','55321')
        [IO.File]::WriteAllText($_.FullName,$data)
    }
if ($Start) {
    $cli = Get-Command supabase -ErrorAction SilentlyContinue
    if ($cli) { $env:SUPABASE_CLI = $cli.Source }
    elseif (!$env:SUPABASE_CLI) {
        Push-Location -LiteralPath $source
        try {
            # stdin preserves JavaScript quotes in Windows PowerShell 5.1 too.
            $resolver = @'
const p = require("node:path");
const suffix = process.platform === "win32" ? "windows" : process.platform === "darwin" ? "darwin" : "linux";
const root = p.dirname(require.resolve("@supabase/cli-" + suffix + "-" + process.arch + "/package.json"));
console.log(p.join(root, "bin", "supabase" + (process.platform === "win32" ? ".exe" : "")));
'@
            $env:SUPABASE_CLI = $resolver | node --input-type=commonjs
            if ($LASTEXITCODE -ne 0) { throw 'Pinned Supabase CLI unavailable.' }
        } finally { Pop-Location }
    }
    $version = & $env:SUPABASE_CLI --version 2>$null
    if ($version -ne '2.117.0') { throw 'Expected Supabase CLI 2.117.0.' }
    # start may print development keys: capture and never emit them.
    $null = & $env:SUPABASE_CLI start --workdir $target 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Disposable Supabase start failed; inspect container health locally.' }
}
Write-Output $target
