param([Parameter(Mandatory=$true)][string]$Serial, [string]$QrImage)
$ErrorActionPreference = 'Stop'
$sdkPath = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/sdk' }
$adbPath = Join-Path $sdkPath 'platform-tools/adb.exe'
$deviceXml = '/sdcard/Download/certichain-8d-camera-' + [Guid]::NewGuid().ToString('N') + '.xml'
$installed = $false
. "$PSScriptRoot/native_adb.ps1"
if ($QrImage) { $QrImage = ResolveNativeQrImage $QrImage }
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
        $node = UiNodes | Where-Object $Predicate | Select-Object -First 1
        if ($node) { return $node }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Native UI predicate timed out: $script:stage"
}
function TapNode($Node) {
    if ($Node.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw 'Invalid UI bounds' }
    $x = [int]( ([int]$Matches[1]+[int]$Matches[3])/2 )
    $y = [int]( ([int]$Matches[2]+[int]$Matches[4])/2 )
    $null = Adb -Parameters @('shell','input','tap',"$x","$y")
}
try {
    if (Adb -Parameters @('shell','pm','list','packages','com.example.mobile')) { throw 'Probe package exists; use an isolated test emulator' }
    $null = Adb -Parameters @('install','-t','build/app/outputs/flutter-apk/app-debug.apk')
    $installed = $true
    $null = Adb -Parameters @('shell','am','start','-n','com.example.mobile/.MainActivity')
    TapNode (WaitNode { $_.text -eq 'Open production scanner' -or $_.'content-desc' -eq 'Open production scanner' })
    $script:stage='deny-dialog'
    TapNode (WaitNode { $_.'resource-id' -match 'permission_deny_button' -or $_.text -eq "Don't allow" -or $_.text -eq 'Deny' -or $_.text -eq 'No permitir' })
    $script:stage='denied-result'
    $null = WaitNode { $_.text -like '*Permiso de cámara denegado*' -or $_.'content-desc' -like '*Permiso de cámara denegado*' }
    $null = Adb -Parameters @('shell','pm','grant','com.example.mobile','android.permission.CAMERA')
    TapNode (WaitNode { $_.text -eq 'Activar cámara' -or $_.'content-desc' -eq 'Activar cámara' })
    $script:stage='camera-reading'
    $null = WaitNode { $_.text -like '*Leyendo QR*' -or $_.'content-desc' -like '*Leyendo QR*' }
    $null = Adb -Parameters @('shell','input','keyevent','KEYCODE_HOME')
    Start-Sleep -Milliseconds 500
    $null = Adb -Parameters @('shell','am','start','-n','com.example.mobile/.MainActivity')
    $script:stage='background-pause'
    $null = WaitNode { $_.text -like '*Cámara detenida*' -or $_.'content-desc' -like '*Cámara detenida*' }
    TapNode (WaitNode { $_.text -eq 'Activar cámara' -or $_.'content-desc' -eq 'Activar cámara' })
    $null = WaitNode { $_.text -like '*Leyendo QR*' -or $_.'content-desc' -like '*Leyendo QR*' }
    TapNode (WaitNode { $_.text -like '*Cancelar escáner*' -or $_.'content-desc' -like '*Cancelar escáner*' })
    $null = WaitNode { $_.text -eq 'Open production scanner' -or $_.'content-desc' -eq 'Open production scanner' }
    if ($QrImage) {
        $null = Adb -Parameters @('emu','virtualscene-image','wall',$QrImage)
        TapNode (WaitNode { $_.text -eq 'Open production scanner' -or $_.'content-desc' -eq 'Open production scanner' })
        $script:stage='native-qr-decode'
        TapNode (WaitNode { $_.text -like '*Verificar código identificado*' -or $_.'content-desc' -like '*Verificar código identificado*' })
        $null = WaitNode { $_.text -eq 'Confirmed code' -or $_.'content-desc' -eq 'Confirmed code' }
        Write-Output 'PASS Android ML Kit decoded synthetic QR in emulator virtual scene and confirmed code'
    }
    $null = Adb -Parameters @('shell','pm','revoke' ,'com.example.mobile','android.permission.CAMERA')
    Write-Output 'PASS Android production scanner adapter: denied, later granted, real emulated camera, background pause, explicit resume, close, permission revoked'
} finally {
    if ($QrImage) { $null = Adb -Parameters @('emu','virtualscene-image','wall') }
    if ($installed) { $null = Adb -Parameters @('uninstall','com.example.mobile') }
    $null = Adb -Parameters @('shell','rm','-f',$deviceXml)
}
