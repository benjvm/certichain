param([Parameter(Mandatory=$true)][string]$Serial)
$ErrorActionPreference = 'Stop'
$sdkPath = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/sdk' }
$adbPath = Join-Path $sdkPath 'platform-tools/adb.exe'
$probeId = [Guid]::NewGuid().ToString('N').Substring(0,12)
$inputName = "cc-$probeId.pdf"
$outputName = "cc-save-$probeId.pdf"
$deviceXml = "/sdcard/Download/certichain-7d-$probeId.xml"
$probeDirectory = Join-Path (Get-Location) "build/native-7d-$probeId"
$probeDirectory = [IO.Path]::GetFullPath($probeDirectory)
$buildDirectory = [IO.Path]::GetFullPath((Join-Path (Get-Location) 'build'))
if (!$probeDirectory.StartsWith($buildDirectory + [IO.Path]::DirectorySeparatorChar)) { throw 'Unsafe native fixture directory' }
$expected = [byte[]](37,80,68,70,45,49,46,52,10,7)
$installed = $false
 . "$PSScriptRoot/native_adb.ps1"
function Adb([string[]]$Parameters) {
    return InvokeNativeAdb -AdbPath $adbPath -Serial $Serial -Parameters $Parameters
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
        $nodes = UiNodes
        if ($nodes | Where-Object { $_.text -like 'FAIL native PDF dialogs*' -or $_.'content-desc' -like 'FAIL native PDF dialogs*' }) { throw "Native adapter failed at $script:stage" }
        $node = $nodes | Where-Object $Predicate | Select-Object -First 1
        if ($node) { return $node }
    } while ([DateTime]::UtcNow -lt $deadline)
    $packages = ($nodes | ForEach-Object { $_.package } | Select-Object -Unique) -join ','
    $controls = ($nodes | Where-Object { $_.text -in @('OPEN','Open','SAVE','Save','CANCEL','Cancel','Select synthetic PDF') } | ForEach-Object { $_.text }) -join ','
    throw "Native UI predicate timed out: $script:stage; packages=$packages; controls=$controls"
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
    $null = Adb -Parameters @('shell','input','keyevent','KEYCODE_WAKEUP')
    $null = Adb -Parameters @('shell','wm','dismiss-keyguard')
    New-Item -ItemType Directory -Path $probeDirectory | Out-Null
    $inputFile = Join-Path $probeDirectory $inputName
    [IO.File]::WriteAllBytes($inputFile,$expected)
    $null = Adb -Parameters @('shell','mkdir','-p','/sdcard/Download')
    $null = Adb -Parameters @('push',$inputFile,"/sdcard/Download/$inputName")
    # DocumentsUI's Downloads provider indexes files asynchronously. Explicitly
    # index only this synthetic fixture before opening the filtered PDF chooser.
    $null = Adb -Parameters @('shell','am','broadcast','-a','android.intent.action.MEDIA_SCANNER_SCAN_FILE','-d',"file:///sdcard/Download/$inputName")
    $null = Adb -Parameters @('install','-t','build/app/outputs/flutter-apk/app-debug.apk')
    $installed = $true
    $null = Adb -Parameters @('shell','input','keyevent','KEYCODE_WAKEUP')
    $null = Adb -Parameters @('shell','wm','dismiss-keyguard')
    $null = Adb -Parameters @('shell','am','start','-n','com.example.mobile/.MainActivity')
    $script:stage='cancel-picker'
    TapNode (WaitNode { $_.text -eq 'Cancel PDF selection' -or $_.'content-desc' -eq 'Cancel PDF selection' })
    $null = WaitNode { $_.package -match 'documentsui' }
    $null = Adb -Parameters @('shell','input','keyevent','4')
    $script:stage='select-picker'
    TapNode (WaitNode { $_.text -eq 'Select synthetic PDF' -or $_.'content-desc' -eq 'Select synthetic PDF' })
    $null = WaitNode { $_.package -match 'documentsui' }
    $script:stage='show-roots'
    TapNode (WaitNode { $_.'content-desc' -eq 'Show roots' })
    $script:stage='downloads-root'
    TapNode (WaitNode { $_.text -eq 'Downloads' })
    $script:stage='choose-synthetic-file'
    TapNode (WaitNode { $_.text -eq $inputName })
    $script:stage='save-dialog'
    $field = WaitNode { $_.class -eq 'android.widget.EditText' -and $_.package -match 'documentsui' }
    TapNode $field
    $null = Adb -Parameters @('shell','input','keyevent','KEYCODE_MOVE_END')
    # Select all through Ctrl+A, then set a unique synthetic destination.
    $null = Adb -Parameters @('shell','input','keycombination','113','29')
    $null = Adb -Parameters @('shell','input','text',$outputName)
    TapNode (WaitNode { $_.text -eq 'SAVE' -or $_.text -eq 'Save' })
    $script:stage='saved-bytes-result'
    $null = WaitNode { $_.text -eq 'PASS native PDF dialogs' -or $_.'content-desc' -eq 'PASS native PDF dialogs' }
    $outputFile = Join-Path $probeDirectory $outputName
    $null = Adb -Parameters @('pull',"/sdcard/Download/$outputName",$outputFile)
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($outputFile)) -ne [Convert]::ToBase64String($expected)) { throw 'Native saved bytes differ' }
    $cached = Adb -Parameters @('shell','run-as','com.example.mobile','find','cache','-type','f','-name',$inputName)
    if ($cached) { throw 'Own selected picker copy retained in cache' }
    $null = Adb -Parameters @('pull',"/sdcard/Download/$inputName",$inputFile)
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($inputFile)) -ne [Convert]::ToBase64String($expected)) { throw 'Original selected bytes changed' }
    Write-Output 'PASS Android native dialogs: real cancellation, picker, saver, exact bytes, own cache removed and original retained'
} finally {
    if ($installed) { $null = Adb -Parameters @('uninstall','com.example.mobile') }
    $null = Adb -Parameters @('shell','rm','-f',"/sdcard/Download/$inputName","/sdcard/Download/$outputName",$deviceXml)
    if (Test-Path -LiteralPath $probeDirectory) { Remove-Item -LiteralPath $probeDirectory -Recurse -Force }
}
