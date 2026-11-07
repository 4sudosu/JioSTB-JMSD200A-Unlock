# One-command unlock for Jio STB JMSD200A (Method B: Windows PC Mobile Hotspot)
# Usage:  .\unlock-setupbox.ps1 [-StbIp 192.168.137.89]
# Prereqs: Docker Desktop running, Python 3, Git Bash, ADB (platform-tools) on PATH.
param(
  [string]$StbIp = "192.168.137.89",
  [string]$Gateway = "192.168.137.1"
)
$ErrorActionPreference = "Continue"
$root = $PSScriptRoot
$docker = "docker"; if (!(Get-Command docker -ErrorAction SilentlyContinue)) { $docker = "C:\Program Files\Docker\Docker\resources\bin\docker.exe" }

Write-Host "=== JioSTB JMSD200A unlock (SetupBox) ===" -ForegroundColor Cyan
Write-Host "This automates the lab side. A few physical steps are required (printed below).`n"

# 1) Prereq checks (lightweight)
foreach ($c in @(@{n='python';t='Python 3'}, @{n='adb';t='ADB (platform-tools)'})) {
  if (!(Get-Command $c.n -ErrorAction SilentlyContinue)) { Write-Warning "Missing: $($c.t) - install it and re-run." }
}
$bash = "E:\Git\bin\bash.exe"; if (!(Test-Path $bash)) { $bash = (Get-Command bash -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
if (!$bash -or !(Test-Path $bash)) { Write-Warning "Git Bash not found (needed for stage1.sh). Install Git for Windows." }

# 2) GenieACS
Write-Host "[1/5] GenieACS + Mongo..." -ForegroundColor Yellow
& $docker compose -f "$root\tls\docker-compose.yml" up -d 2>&1 | Out-Host

# 3) pass_front (TLS front)
Write-Host "[2/5] TLS front-end (pass_front.py on :8443/:9443)..." -ForegroundColor Yellow
$listening = Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue
if (!$listening) {
  Start-Process -FilePath "python" -ArgumentList "`"$root\tls\pass_front.py`"" -WorkingDirectory "$root\tls" -WindowStyle Minimized
  Start-Sleep 2
  Write-Host "  started pass_front.py (minimized)."
} else { Write-Host "  already listening." }

# 4) DNS (Method B) - bind to hotspot gateway
Write-Host "[3/5] DNS spoof (dnsmasq -> $Gateway)..." -ForegroundColor Yellow
& $docker rm -f jio-dns 2>&1 | Out-Null
& $docker run -d --name jio-dns --restart unless-stopped -p "${Gateway}:53:53/udp" -p "${Gateway}:53:53/tcp" -v "$root\tls\dns\dnsmasq.conf:/etc/dnsmasq.conf:ro" jpillora/dnsmasq 2>&1 | Out-Host

# 5) Guidance for manual steps
$hasGw = Get-NetIPAddress -IPAddress $Gateway -ErrorAction SilentlyContinue
Write-Host "`n[4/5] MANUAL STEPS (do these now):" -ForegroundColor Magenta
if (!$hasGw) {
  Write-Host "  ! PC hotspot gateway $Gateway not found. Turn ON: Settings > Network & internet > Mobile hotspot (Share over Wi-Fi)." -ForegroundColor Red
} else { Write-Host "  OK: hotspot gateway $Gateway detected." -ForegroundColor Green }
Write-Host @"
  1. Phone's hotspot OFF (Jio phone hotspot hijacks STB provisioning and breaks the redirect).
  2. PC Mobile hotspot ON (Wi-Fi). Keep STB on DHCP - do NOT set static DNS on the STB.
  3. On the STB: connect Wi-Fi to the PC's hotspot name. Note the STB IP (usually $StbIp).
  4. Reboot the STB (power off/on). It will phone home to this PC's fake ACS.
  5. If 'Allow USB debugging?' appears on TV, accept it (tick Always allow).
"@

Write-Host "[5/5] Watching for STB + auto-running Stage 1 (Ctrl+C to stop)..." -ForegroundColor Yellow
Write-Host "  GenieACS NBI: http://127.0.0.1:7557/devices/  |  Target ADB: ${StbIp}:5555`n"
$deadline = (Get-Date).AddMinutes(45); $fired = $false
while ((Get-Date) -lt $deadline -and -not $fired) {
  try { $d = (Invoke-RestMethod -TimeoutSec 5 "http://127.0.0.1:7557/devices/?projection=_id,_lastInform") } catch { $d = @() }
  if ($d -and $d.Count -gt 0) {
    $id = $d[0]._id; Write-Host "DEVICE SEEN: $id" -ForegroundColor Green
    if ($bash -and (Test-Path $bash)) {
      & $bash -lc "cd '$($root -replace '\\','/')' && ./stage1.sh --tasks-only --stb-ip $StbIp" 2>&1 | Out-Host
    } else { Write-Warning "Run manually: ./stage1.sh --tasks-only --stb-ip $StbIp" }
    Write-Host "Polling ADB (port 5555 opens after STB applies task / next Inform)..."
    for ($i=0; $i -lt 90; $i++) {
      $c = adb connect "${StbIp}:5555" 2>&1
      if ($c -match 'connected') { Write-Host $c -ForegroundColor Green; Start-Sleep 6; break }
      Start-Sleep 20
    }
    adb devices | Out-Host
    if ((adb -s "${StbIp}:5555" get-state 2>&1) -match 'device') {
      Write-Host "`nADB READY. Installing Settings shortcut (required)..." -ForegroundColor Green
      adb -s "${StbIp}:5555" install -r "$root\apk\android-settings-shortcut.apk" | Out-Host
      Write-Host "Optional: run .\restore-setup.ps1 -Stb ${StbIp}:5555 to restore apps/settings." -ForegroundColor Cyan
    } else {
      Write-Host "ADB not 'device' yet - accept the TV dialog if shown, or wait one more Inform cycle (~6 min), then: adb connect ${StbIp}:5555" -ForegroundColor Yellow
    }
    $fired = $true; break
  }
  Start-Sleep 10
}
if (-not $fired) { Write-Warning "Timed out waiting for STB (45 min). Check: STB on PC hotspot, DNS working, reboot STB. See AI.md troubleshooting." }
