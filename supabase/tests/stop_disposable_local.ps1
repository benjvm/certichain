param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
if (!$target.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($target) -notmatch '^certichain-8[ad]-[0-9a-f-]{36}$') { throw 'Requires a dedicated disposable directory under the system temporary root.' }
$config = [IO.File]::ReadAllText((Join-Path $target 'supabase/config.toml'))
$project = [regex]::Match($config, '^project_id\s*=\s*"([^"]+)"', [Text.RegularExpressions.RegexOptions]::Multiline).Groups[1].Value
if ($project -notmatch '^certichain_8[ad]_[0-9a-f]{8}$') { throw 'Refusing to stop a non-disposable project.' }
if (!$env:SUPABASE_CLI) { throw 'Set SUPABASE_CLI to the pinned executable.' }
$null = & $env:SUPABASE_CLI stop --no-backup --workdir $target 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Disposable stop failed; directory retained for inspection.' }
Remove-Item -LiteralPath $target -Recurse -Force
Write-Output 'PASS own disposable stack stopped and directory removed'
