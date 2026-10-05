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
        if ($process.ExitCode -ne 0) {
            $category = [regex]::Match($result, 'INSTALL_FAILED_[A-Z_]+').Value
            if (!$category) {
                $category = if ($result -match 'Permission denied') { 'permission' } elseif ($result -match 'No such file|cannot stat') { 'missing_path' } elseif ($result -match 'offline|not found') { 'device_unavailable' } else { 'other' }
            }
            throw "ADB failed: operation=$($Parameters[0]); category=$category"
        }
        return $result.Trim()
    } finally { $process.Dispose() }
}
