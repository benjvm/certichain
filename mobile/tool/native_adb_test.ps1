$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/native_adb.ps1"
foreach ($response in @('KO cannot load private/path', "notice`nKO: credential")) {
    $failed = $false
    try { AssertNativeAdbResult -Parameters @('emu','virtualscene-image') -ExitCode 0 -Result $response }
    catch {
        $failed = $true
        if ($_.Exception.Message -ne 'ADB failed: operation=emu; category=console_rejected') { throw 'Unsanitized console diagnostic' }
    }
    if (!$failed) { throw 'Emulator KO exit 0 accepted' }
}
AssertNativeAdbResult -Parameters @('emu','virtualscene-image') -ExitCode 0 -Result "OK`r`n"
AssertNativeAdbResult -Parameters @('shell','cat') -ExitCode 0 -Result 'KO is valid file content'
$failed = $false
try { AssertNativeAdbResult -Parameters @('install') -ExitCode 1 -Result 'private INSTALL_FAILED_INSUFFICIENT_STORAGE' }
catch {
    $failed = $true
    if ($_.Exception.Message -ne 'ADB failed: operation=install; category=INSTALL_FAILED_INSUFFICIENT_STORAGE') { throw 'Unexpected install diagnostic' }
}
if (!$failed) { throw 'Install failure accepted' }
$taskRoot = Join-Path ([IO.Path]::GetTempPath()) ('certichain-qr-path-' + [guid]::NewGuid())
$taskFile = Join-Path $taskRoot 'synthetic [qr].png'
New-Item -ItemType Directory -Path $taskRoot | Out-Null
[IO.File]::WriteAllBytes($taskFile, [byte[]]@(0))
Push-Location -LiteralPath $taskRoot
try {
    if ((ResolveNativeQrImage './synthetic [qr].png') -ne $taskFile) { throw 'QR resolved against process cwd instead of PowerShell location' }
    $failed = $false
    try { $null = ResolveNativeQrImage './missing.png' }
    catch {
        $failed = $true
        if ($_.Exception.Message -ne 'Synthetic QR image is missing.') { throw 'Unsanitized fixture diagnostic' }
    }
    if (!$failed) { throw 'Missing QR image accepted' }
} finally {
    Pop-Location
    Remove-Item -LiteralPath $taskFile -Force
    Remove-Item -LiteralPath $taskRoot -Force
}
Write-Output 'PASS 7 native regressions: console KO exit 0, valid OK/shell data, sanitized install failure, literal relative QR path and absent fixture'
