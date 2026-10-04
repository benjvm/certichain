param([Parameter(Mandatory=$true)][string]$Serial)
$ErrorActionPreference = 'Stop'
$sdkPath = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/sdk' }
$adbPath = Join-Path $sdkPath 'platform-tools/adb.exe'
$probeId = [Guid]::NewGuid().ToString('N')
$inputName = "certichain-7d-$probeId.pdf"
$outputName = "certichain-7d-saved-$probeId.pdf"
$deviceXml = "/sdcard/Download/certichain-7d-$probeId.xml"
$probeDirectory = Join-Path (Get-Location) "build/native-7d-$probeId"
$probeDirectory = [IO.Path]::GetFullPath($probeDirectory)
$buildDirectory = [IO.Path]::GetFullPath((Join-Path (Get-Location) 'build'))
if (!$probeDirectory.StartsWith($buildDirectory + [IO.Path]::DirectorySeparatorChar)) { throw 'Unsafe native fixture directory' }
$expected = [byte[]](37,80,68,70,45,49,46,52,10,7)
$installed = $false
function Adb([string[]]$Parameters) {
    $result = & $adbPath -s $Serial @Parameters 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ADB probe operation failed ($($Parameters[0]) $($Parameters[1]))" }
    return ($result -join "`n")
}
function UiNodes {
    $null = Adb -Parameters @('shell','uiautomator','dump',$deviceXml)
    try { [xml]$tree = Adb -Parameters @('shell','cat',$deviceXml) }
    catch { return @() } # A transition can temporarily have no idle hierarchy.
    return $tree.SelectNodes('//node')
}
function WaitNode([scriptblock]$Predicate) {
    $deadline = [DateTime]::UtcNow.AddSeconds(40)
    do {
        $node = UiNodes | Where-Object $Predicate | Select-Object -First 1
        if ($node) { return $node }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Native UI predicate timed out'
}
function TapNode($Node) {
    if ($Node.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw 'Invalid UI bounds' }
    $x = [int]( ([int]$Matches[1]+[int]$Matches[3])/2 )
    $y = [int]( ([int]$Matches[2]+[int]$Matches[4])/2 )
    $null = Adb -Parameters @('shell','input','tap',"$x","$y")
}
try {
    # Never overwrite or uninstall an app already belonging to this device.
    if (Adb -Parameters @('shell','pm','list','packages','com.example.mobile')) { throw 'Probe package already exists; use an isolated test device' }
    New-Item -ItemType Directory -Path $probeDirectory | Out-Null
    $inputFile = Join-Path $probeDirectory $inputName
    [IO.File]::WriteAllBytes($inputFile,$expected)
    $null = Adb -Parameters @('push',$inputFile,"/sdcard/Download/$inputName")
    $null = Adb -Parameters @('install','-t','build/app/outputs/flutter-apk/app-debug.apk')
    $installed = $true
    $null = Adb -Parameters @('shell','input','keyevent','KEYCODE_WAKEUP')
    $null = Adb -Parameters @('shell','wm','dismiss-keyguard')
    $null = Adb -Parameters @('shell','am','start','-n','com.example.mobile/.MainActivity')
    TapNode (WaitNode { $_.text -eq 'Cancel PDF selection' -or $_.'content-desc' -eq 'Cancel PDF selection' })
    $null = WaitNode { $_.package -match 'documentsui' }
    $null = Adb -Parameters @('shell','input','keyevent','4')
    TapNode (WaitNode { $_.text -eq 'Select synthetic PDF' -or $_.'content-desc' -eq 'Select synthetic PDF' })
    $null = WaitNode { $_.package -match 'documentsui' }
    TapNode (WaitNode { $_.'content-desc' -eq 'Show roots' })
    TapNode (WaitNode { $_.text -eq 'Downloads' })
    TapNode (WaitNode { $_.text -eq $inputName })
    $field = WaitNode { $_.class -eq 'android.widget.EditText' -and $_.package -match 'documentsui' }
    TapNode $field
    $null = Adb -Parameters @('shell','input','keyevent','KEYCODE_MOVE_END')
    # Select all through Ctrl+A, then set a unique synthetic destination.
    $null = Adb -Parameters @('shell','input','keycombination','113','29')
    $null = Adb -Parameters @('shell','input','text',$outputName)
    TapNode (WaitNode { $_.text -eq 'SAVE' -or $_.text -eq 'Save' })
    $null = WaitNode { $_.text -eq 'PASS native PDF dialogs' -or $_.'content-desc' -eq 'PASS native PDF dialogs' }
    $outputFile = Join-Path $probeDirectory $outputName
    $null = Adb -Parameters @('pull',"/sdcard/Download/$outputName",$outputFile)
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($outputFile)) -ne [Convert]::ToBase64String($expected)) { throw 'Native saved bytes differ' }
    Write-Output 'PASS Android native dialogs: real cancellation, picker, saver and exact saved bytes'
} finally {
    if ($installed) { $null = Adb -Parameters @('uninstall','com.example.mobile') }
    $null = Adb -Parameters @('shell','rm','-f',"/sdcard/Download/$inputName","/sdcard/Download/$outputName",$deviceXml)
    if (Test-Path -LiteralPath $probeDirectory) { Remove-Item -LiteralPath $probeDirectory -Recurse -Force }
}
