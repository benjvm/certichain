function ResolveNativeQrImage([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Synthetic QR image is missing.' }
    # Resolve-Path follows PowerShell's location, unlike GetFullPath(relative).
    return (Resolve-Path -LiteralPath $Path).ProviderPath
}

function AssertNativeAdbResult([string[]]$Parameters, [int]$ExitCode, [string]$Result) {
    # The emulator console reports rejected commands as KO even with exit 0.
    if ($Parameters[0] -eq 'emu' -and $Result -match '(?m)^KO(?:\s|:)') {
        throw 'ADB failed: operation=emu; category=console_rejected'
    }
    if ($ExitCode -ne 0) {
        $category = [regex]::Match($Result, 'INSTALL_FAILED_[A-Z_]+').Value
        if (!$category) {
            $category = if ($Result -match 'Permission denied') { 'permission' } elseif ($Result -match 'No such file|cannot stat') { 'missing_path' } elseif ($Result -match 'offline|not found') { 'device_unavailable' } else { 'other' }
        }
        throw "ADB failed: operation=$($Parameters[0]); category=$category"
    }
}

function InvokeNativeAdb([string]$AdbPath, [string]$Serial, [string[]]$Parameters) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $AdbPath
    $info.WorkingDirectory = (Get-Location).ProviderPath
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in @('-s',$Serial) + $Parameters) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        $null = $process.Start()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        $limit = if ($Parameters[0] -eq 'install') { 90000 } elseif ($Parameters -contains 'uiautomator') { 10000 } else { 30000 }
        if (!$process.WaitForExit($limit)) {
            $process.Kill($true)
            $null = $process.WaitForExit(2000)
            throw "ADB deadline: operation=$($Parameters[0])"
        }
        $result = $output.GetAwaiter().GetResult() + $errors.GetAwaiter().GetResult()
        AssertNativeAdbResult -Parameters $Parameters -ExitCode $process.ExitCode -Result $result
        return $result.Trim()
    } finally { $process.Dispose() }
}
