param([string]$TemplateAvd = 'Pixel_2')
$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$directory = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('certichain-9e-native-' + [guid]::NewGuid())))
$sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/sdk' }
$adb = Join-Path $sdk 'platform-tools/adb.exe'
$emulator = Join-Path $sdk 'emulator/emulator.exe'
$saved = @{}
foreach ($name in @('CERTICHAIN_TEST_CAMERA','ANDROID_AVD_HOME','ANDROID_USER_HOME','GRADLE_OPTS')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
$child = $null
$installed = $false
$serial = 'emulator-5580'
$serverPort = '5039'
$result = 'FAIL'
$stage = 'prepare'
function Adb([string[]]$Parameters) {
  $output = & $adb -P $serverPort -s $serial @Parameters 2>&1
  if ($LASTEXITCODE -ne 0 -or ($Parameters[0] -eq 'emu' -and $output -match '(?m)^KO')) { throw "Owned native ADB failure: $stage" }
  return ($output -join "`n").Trim()
}
function Nodes {
  $null = Adb -Parameters @('shell','uiautomator','dump','/sdcard/Download/phase9e-ui.xml')
  try { [xml]$tree = Adb -Parameters @('shell','cat','/sdcard/Download/phase9e-ui.xml') }
  catch { return @() }
  return $tree.SelectNodes('//node')
}
function WaitNode([scriptblock]$Predicate) {
  $deadline = [DateTime]::UtcNow.AddSeconds(35)
  do {
    $nodes = Nodes
    if ($nodes | Where-Object { $_.text -eq 'FAIL native opening files' -or $_.'content-desc' -eq 'FAIL native opening files' }) {
      $diagnostic = Adb -Parameters @('logcat','-d','-s','flutter:I')
      $diagnostic -split "`n" | Where-Object { $_ -match 'Native files failure stage=' } | ForEach-Object { Write-Host $_ }
      throw "Native probe failed: $stage"
    }
    $node = $nodes | Where-Object $Predicate | Select-Object -First 1
    if ($node) { return $node }
  } while ([DateTime]::UtcNow -lt $deadline)
  $known = @('Cancel JSON import','Cancel JSON export','Export synthetic opening','Import exported opening','Cancel PDF selection','Select original PDF','Select altered PDF','FAIL native opening files')
  Write-Host ("Native controls at deadline: " + (($nodes | ForEach-Object { $_.text; $_.'content-desc' } | Where-Object { $_ -in $known }) -join ','))
  Write-Host ("Native packages at deadline: " + (($nodes | ForEach-Object { $_.package } | Select-Object -Unique) -join ','))
  $diagnostic = Adb -Parameters @('logcat','-d','-s','flutter:I')
  $diagnostic -split "`n" | Where-Object { $_ -match 'Native files failure stage=' } | ForEach-Object { Write-Host $_ }
  throw "Native dialog deadline: $stage"
}
function Tap($Node) {
  if ($Node.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw 'Invalid native bounds' }
  $horizontal = [int](([int]$Matches[1]+[int]$Matches[3])/2)
  $vertical = [int](([int]$Matches[2]+[int]$Matches[4])/2)
  Write-Host "Native tap: $stage ($horizontal,$vertical)"
  $null = Adb -Parameters @('shell','input','tap',[string]$horizontal,[string]$vertical)
}
function Control([string]$Text) { Tap (WaitNode { $_.text -eq $Text -or $_.'content-desc' -eq $Text }) }
function Downloads {
  Tap (WaitNode { $_.'content-desc' -eq 'Show roots' })
  Tap (WaitNode { $_.text -eq 'Downloads' })
}
Push-Location -LiteralPath $source
try {
  $env:CERTICHAIN_TEST_CAMERA = '0'
  $env:GRADLE_OPTS = (($env:GRADLE_OPTS + ' -Dorg.gradle.daemon=false').Trim())
  New-Item -ItemType Directory -Path $directory | Out-Null
  $env:ANDROID_USER_HOME = Join-Path $directory 'android-user'
  New-Item -ItemType Directory -Path $env:ANDROID_USER_HOME | Out-Null
  $env:ANDROID_AVD_HOME = Join-Path $directory 'avds'
  $avdName = 'certichain9e'
  $avdPath = Join-Path $env:ANDROID_AVD_HOME "$avdName.avd"
  New-Item -ItemType Directory -Path $avdPath -Force | Out-Null
  $template = Join-Path $env:USERPROFILE ".android/avd/$TemplateAvd.avd/config.ini"
  $config = [IO.File]::ReadAllLines($template) | Where-Object { $_ -notmatch '^(AvdId|avd.ini.displayname|disk.dataPartition|disk.cachePartition|sdcard|hw.sdCard|hw.camera)' }
  [IO.File]::WriteAllLines((Join-Path $avdPath 'config.ini'), @($config) + @("AvdId=$avdName","avd.ini.displayname=$avdName",'disk.dataPartition.size=2G','hw.sdCard=no','hw.camera.back=none','hw.camera.front=none'))
  [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME "$avdName.ini"), "avd.ini.encoding=UTF-8`npath=$avdPath`ntarget=android-34`n")
  $listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
  if ($listeners | Where-Object { $_.LocalPort -in @(5039,5580,5581) }) { throw 'Owned emulator/ADB ports occupied; do not stop unrelated processes.' }
  $fixture = Get-Content blockchain/fixtures/protocol-v1.json -Raw | ConvertFrom-Json
  $opening = @{ protocol_version=1; credential_code=$fixture.credential_code; issuer_id=$fixture.issuer_id; document_sha256=$fixture.document_sha256; salt=$fixture.salt; chain_id='31337'; contract_address=('0x'+('11'*20)) }
  $evidence = @{ state='confirmed'; finality='not_applicable'; checked_at='2026-10-14T00:00:00Z'; source='backend_rpc'; chain_id='31337'; contract_address=$opening.contract_address; protocol_version=1; certificate_key=$fixture.certificate_key; issuer_id=$fixture.issuer_id; commitment=$fixture.commitment; revoked=$false; transaction_hash=('0x'+('22'*32)); block_number='12'; block_hash=('0x'+('33'*32)); confirmations='1'; registered_at='2026-10-13T00:00:00Z' }
  $defines = Join-Path $directory 'synthetic-defines.json'
  @{ PHASE9E_OPENING=($opening | ConvertTo-Json -Compress); PHASE9E_EVIDENCE=($evidence | ConvertTo-Json -Compress) } | ConvertTo-Json -Compress | Set-Content -LiteralPath $defines -Encoding utf8
  $stage = 'build-adapter-probe'
  Push-Location mobile
  try {
    flutter build apk --debug --target=tool/opening_native_smoke.dart "--dart-define-from-file=$defines"
    if ($LASTEXITCODE -ne 0) { throw 'Native adapter build failed' }
  } finally { Pop-Location }
  $child = Start-Process -FilePath $emulator -ArgumentList @('-avd',$avdName,'-port','5580','-no-window','-no-snapshot','-no-audio','-no-boot-anim','-camera-back','none','-camera-front','none','-gpu','swiftshader_indirect') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directory 'emulator-out.txt') -RedirectStandardError (Join-Path $directory 'emulator-error.txt')
  $stage = 'boot-owned-emulator'
  $deadline = [DateTime]::UtcNow.AddSeconds(120)
  do {
    if ($child.HasExited) { throw 'Owned emulator exited before boot' }
    $boot = & $adb -P $serverPort -s $serial shell getprop sys.boot_completed 2>$null
    if ($boot -eq '1') { break }
    Start-Sleep -Seconds 1
  } while ([DateTime]::UtcNow -lt $deadline)
  if ($boot -ne '1') { throw 'Owned emulator boot deadline' }
  $null = Adb -Parameters @('shell','input','keyevent','KEYCODE_WAKEUP')
  $null = Adb -Parameters @('shell','settings','put','system','screen_off_timeout','180000')
  $null = Adb -Parameters @('shell','wm','dismiss-keyguard')
  if (Adb -Parameters @('shell','pm','list','packages','com.example.mobile')) { throw 'Own emulator already has probe package' }
  $original = [IO.File]::ReadAllBytes((Join-Path $source 'blockchain/fixtures/synthetic.pdf'))
  [IO.File]::WriteAllBytes((Join-Path $directory 'original.pdf'),$original)
  $modified = [byte[]]$original.Clone(); $modified[$modified.Length-1] = $modified[$modified.Length-1] -bxor 1
  [IO.File]::WriteAllBytes((Join-Path $directory 'modified.pdf'),$modified)
  foreach ($name in @('original.pdf','modified.pdf')) {
    $null = Adb -Parameters @('push',(Join-Path $directory $name),"/sdcard/Download/$name")
    $null = Adb -Parameters @('shell','am','broadcast','-a','android.intent.action.MEDIA_SCANNER_SCAN_FILE','-d',"file:///sdcard/Download/$name")
  }
  $null = Adb -Parameters @('install','-t',(Join-Path $source 'mobile/build/app/outputs/flutter-apk/app-debug.apk'))
  $installed = $true
  $null = Adb -Parameters @('shell','am','start','-n','com.example.mobile/.MainActivity')
  foreach ($cancel in @('Cancel JSON import','Cancel JSON export')) {
    $stage = $cancel; Control $cancel
    $null = WaitNode { $_.package -match 'documentsui' }
    Start-Sleep -Milliseconds 800
    $null = Adb -Parameters @('shell','input','keyevent','4')
  }
  $stage = 'export-json'; Control 'Export synthetic opening'; Downloads
  $field = WaitNode { $_.class -eq 'android.widget.EditText' -and $_.package -match 'documentsui' }
  Tap $field
  $null = Adb -Parameters @('shell','input','keyevent','KEYCODE_MOVE_END')
  $null = Adb -Parameters @('shell','input','keycombination','113','29')
  $null = Adb -Parameters @('shell','input','text','phase9e-opening.json')
  Control 'SAVE'
  $stage = 'import-json'; Control 'Import exported opening'; Downloads; Control 'phase9e-opening.json'
  $stage = 'cancel-pdf'; Control 'Cancel PDF selection'
  $null = WaitNode { $_.package -match 'documentsui' }
  Start-Sleep -Milliseconds 800
  $null = Adb -Parameters @('shell','input','keyevent','4')
  foreach ($choice in @(@('Select original PDF','original.pdf'),@('Select altered PDF','modified.pdf'))) {
    $stage = $choice[0]; Control $choice[0]; Downloads; Control $choice[1]
  }
  $null = WaitNode { $_.text -eq 'PASS native opening files' -or $_.'content-desc' -eq 'PASS native opening files' }
  $stage = 'original-conservation'
  $null = Adb -Parameters @('pull','/sdcard/Download/original.pdf',(Join-Path $directory 'original-returned.pdf'))
  if ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $directory 'original-returned.pdf'))) -ne [Convert]::ToBase64String($original)) { throw 'Original synthetic bytes modified' }
  $result = 'PASS'
  Write-Output 'PASS Android native adapters: JSON cancellation/export/import; PDF cancellation/original match/altered mismatch; original preserved. Synthetic evidence only; no real native Auth/Anvil journey.'
} finally {
  try {
    if ($installed) { $null = Adb -Parameters @('uninstall','com.example.mobile') }
  } finally {
    if ($child -and !$child.HasExited) { $child.Kill($true); $child.WaitForExit(10000) | Out-Null; Start-Sleep -Milliseconds 1500 }
    $null = & $adb -P $serverPort kill-server 2>&1
    $summary = @{ result=$result; stage=$stage; source_commit=(git rev-parse HEAD); working_tree_dirty=((git status --porcelain).Length -gt 0); evaluated_at=[DateTime]::UtcNow.ToString('o'); scope='native-file-adapters-synthetic-vector'; camera='NOT_RUN'; camera_reason='Omitidas por instrucción del usuario; no hay cámara física disponible' }
    New-Item -ItemType Directory -Path mobile/build/phase9e-evidence -Force | Out-Null
    $summary | ConvertTo-Json | Set-Content mobile/build/phase9e-evidence/android.json -Encoding utf8
    try {
      $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
      if (!$directory.StartsWith($tempRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($directory) -notmatch '^certichain-9e-native-[0-9a-f-]{36}$') { throw 'Unsafe owned native cleanup target' }
      if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
      $summary.cleanup = 'PASS'
      $summary | ConvertTo-Json | Set-Content mobile/build/phase9e-evidence/android.json -Encoding utf8
    } finally {
      foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
      Pop-Location
    }
  }
}
