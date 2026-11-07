param(
  [string]$Stb = "192.168.137.89:5555",
  [string]$ApkDir = "$PSScriptRoot\user-apks"
)
$ErrorActionPreference = "Continue"
adb connect $Stb 2>&1 | Out-Null
$state = adb -s $Stb get-state 2>&1
if ($state -notmatch 'device') { Write-Error "ADB not ready for $Stb (state=$state). Connect box + accept 'Allow USB debugging'."; exit 1 }
Write-Host "== Restoring setup on $Stb =="

Write-Host "[1/4] System settings"
adb -s $Stb shell settings put global verifier_verify_adb_installs 0 | Out-Null
adb -s $Stb shell settings put secure install_non_market_apps 1 | Out-Null
# Remote YouTube button -> SmartTube (Jio premium remote mapping)
$rk = '[{"applicationName":"Hotstar","keycode":138,"packageName":"in.startv.hotstar"},{"applicationName":"Netflix","keycode":137,"packageName":"com.netflix.ninja"},{"applicationName":"PrimeVideo","keycode":134,"packageName":"com.amazon.amazonvideo.livingroom"},{"applicationName":"SonyLiv","keycode":141,"packageName":"com.jiotv.sonyliv"},{"applicationName":"Zee5","keycode":142,"packageName":"com.zee5.aosp"},{"applicationName":"SmartTube","keycode":140,"packageName":"org.smarttube.stable"}]'
$tmp = Join-Path $env:TEMP "jio_rk_$(Get-Random).json"
[IO.File]::WriteAllText($tmp, $rk)
adb -s $Stb push $tmp /sdcard/jio_rk.json 2>&1 | Out-Null
$rsh = Join-Path $env:TEMP "jio_rk_$(Get-Random).sh"
[IO.File]::WriteAllText($rsh, 'settings put global jio_premium_remote_setup_complete "$(cat /sdcard/jio_rk.json)"' + "`n")
adb -s $Stb push $rsh /data/local/tmp/jio_rk.sh 2>&1 | Out-Null
adb -s $Stb shell "sh /data/local/tmp/jio_rk.sh" 2>&1 | Out-Null
Remove-Item $tmp,$rsh -ErrorAction SilentlyContinue
Write-Host "  verifier=0, install_non_market_apps=1, YouTube remote button -> SmartTube"

Write-Host "[2/4] Bundled required apps (Settings shortcut, YouTube button -> SmartTube)"
adb -s $Stb install -r "$PSScriptRoot\apk\android-settings-shortcut.apk" | Out-Null
adb -s $Stb install -r "$PSScriptRoot\apk\youtube-button-remap.apk" | Out-Null
adb -s $Stb shell settings put secure enabled_accessibility_services com.jiostb.youtubebutton/.YouTubeButtonService | Out-Null
adb -s $Stb shell settings put secure accessibility_enabled 1 | Out-Null
Write-Host "  Settings shortcut + YouTube button remap (accessibility) installed/enabled"

function Install-Match($name, $pattern) {
  $f = Get-ChildItem -Path $ApkDir -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($f) { Write-Host "  installing $name: $($f.FullName)"; adb -s $Stb install -r $f.FullName } 
  else { Write-Host "  MISSING $name -> put in $ApkDir ($pattern)"; $script:miss = $true }
}

Write-Host "[3/4] User APKs from $ApkDir (provide your own; see setup-manifest.json)"
New-Item -ItemType Directory -Force -Path $ApkDir | Out-Null
$script:miss = $false
Install-Match "SmartTube (armeabi-v7a)" "*SmartTube*armeabi-v7a*.apk"
Install-Match "Kartoons" "*kartoons*.apk"
Install-Match "NetMirror (Android TV)" "*netmirror*.apk"
Install-Match "Send Files to TV" "*send*files*tv*.apk"
# optional
$f = Get-ChildItem -Path $ApkDir -Filter "*aptoide*.apk" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($f) { Write-Host "  installing Aptoide: $($f.FullName)"; adb -s $Stb install -r $f.FullName } else { Write-Host "  (optional) Aptoide not found in $ApkDir (*aptoide*.apk)" }

Write-Host "[4/4] Send Files to TV install permission (direct APK installs on box)"
$pkgs = adb -s $Stb shell pm list packages 2>&1
if ($pkgs -match 'com\.yablio\.sendfilestotv') {
  adb -s $Stb shell appops set com.yablio.sendfilestotv REQUEST_INSTALL_PACKAGES allow | Out-Null
  Write-Host "  REQUEST_INSTALL_PACKAGES=allow"
} else { Write-Host "  skipped (Send Files to TV not installed)" }

Write-Host "== Done =="
adb -s $Stb shell pm list packages | Select-String "smarttube|kartoons|netmirror|sendfilestotv|settingshortcut"
if ($script:miss) { Write-Host "Some APKs missing - add them to $ApkDir and re-run (safe to re-run)." } else { Write-Host "All apps restored." }
Write-Host "Note: Jio launcher home-pin order is not auto-restored (launcher keeps its own config)."
