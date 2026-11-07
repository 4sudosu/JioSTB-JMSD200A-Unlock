# AI.md — Operations manual for AI agents working on JioSTB (JMSD200A)

> This file is written for **AI agents / automation** (Claude, Codex, etc.) that are asked to
> "unlock the Jio box", "install apps on the STB", or debug a failed unlock.
> It contains the full procedure, the exact file/paths involved, and **every error we
> actually hit** with its resolution. Device under test: **JMSD200A**, Android 11,
> security patch `2024-06-05`, serial `08BB3C-JMSD200A-RFLSBEKN6255094`.

---

## 0. Context you must know before acting

- The firmware (JioOS, Android TV 11 fork) **has no ADB toggles** in Developer options. ADB
  over network is gated by a TR‑069 parameter (`Device.JioSTB.USB.USBDebugging`) that only
  Jio's ACS server sets. The whole unlock = impersonate that server.
- The box contacts `https://acs.oss.jio.com:8443` (TR-069/CWMP). TLS is terminated by
  `tls/pass_front.py` using the included RILROOTCA chain; the inner session goes to
  GenieACS (ports: CWMP 7547, NBI 7557, web UI 3000).
- **Inform interval ≈ 360 s.** Tasks queued via NBI apply on the *next* Inform. A reboot
  forces an immediate Inform — cheapest way to trigger.
- Expected success signature in `adb devices`: `192.168.x.x:5555   device`
  (a transient `unauthorized` right after stale re-connects is normal — an
  "Allow USB debugging?" dialog may appear on the TV screen; wait, don't panic,
  re-run `adb connect` after the user accepts it).

### Environment facts (Windows 11 PC, Wi‑Fi only)

| Thing | Value / gotcha |
|---|---|
| Python | `python` exists, `python3` is a Microsoft Store stub. **Fix:** shim at `%USERPROFILE%\.local\bin\python3` (bash script) exec-ing the real `python.exe` — stage1.sh needs `python3` inside Git Bash. |
| Git Bash | lives at `E:\Git\bin\bash.exe` on some machines; plain `bash` may resolve to a broken WSL stub. Use the full path. |
| Docker CLI | installed but not on PATH for fresh shells: use `C:\Program Files\Docker\Docker\resources\bin\docker.exe` or prepend that dir to `$env:Path` in every shell. WSL2 kernel missing after Docker install → `wsl --update`. |
| Credentials | `~/.docker/config.json` has `credsStore: desktop`; pulls fail with `docker-credential-desktop: not found in %PATH%` until the bin folder is on PATH. |

---

## 1. The two working network topologies

### Method A — home router (classic)

Box and PC on the same LAN. Set the box's static DNS 1/2 to the PC's IP using the box's
hidden stock Settings (USB-trick: My Music → Settings → Eject USB → Internal storage →
Apps → Settings gear → Network → Wi-Fi → Advanced IP settings → DHCP→Static).
Run a dnsmasq container bound to the PC IP answering `jio.com` with the PC IP
(`tls/dns/dnsmasq.conf`).

### Method B — Windows Mobile Hotspot (no router at all) ✅ *verified end‑to‑end*

1. **Phone's hotspot must be OFF.** A Jio phone's hotspot hijacks the STB's provisioning
   path natively (observed: box tunnels to the phone on TCP port **7443** and to
   `20.244.153.94:443`); the DNS redirect never happens there. This single fact cost an
   entire debugging session.
2. PC: *Settings → Network & internet → Mobile hotspot → ON*.
   The ICS adapter appears as `Local Area Connection* <n>`, host IP `192.168.137.1`.
3. STB: connect to the PC's hotspot SSID, **leave DHCP** — never use static on this net.
4. PC can still have its internet from tethering/another adapter; irrelevant to the box.
5. Bind the DNS container **specifically** to `192.168.137.1:53`:

```powershell
$env:Path = "C:\Program Files\Docker\Docker\resources\bin;" + $env:Path
docker rm -f jio-dns
docker run -d --name jio-dns --restart unless-stopped `
  -p 192.168.137.1:53:53/udp -p 192.168.137.1:53:53/tcp `
  -v "$env:USERPROFILE\Downloads\sideload-jiostb\tls\dns\dnsmasq.conf:/etc/dnsmasq.conf:ro" `
  jpillora/dnsmasq
```

with

```
# tls/dns/dnsmasq.conf
address=/jio.com/192.168.137.1
server=<upstream DNS IP>
```

**Why the specific bind matters:** Windows ICS runs its own DNS proxy on `0.0.0.0:53`
(svchost). Our socket coexists under SO_REUSEADDR, and Windows routes unicast DNS to the
*more specific* binding → our dnsmasq wins for clients on the hotspot subnet. Verified:
`Resolve-DnsName acs.oss.jio.com -Server 192.168.137.1` → answers `192.168.137.1`.

---

## 2. Bring-up sequence (exact commands)

```powershell
# 1) GenieACS + Mongo
Set-Location "$env:USERPROFILE\Downloads\sideload-jiostb\tls"
docker compose up -d          # pulls mongo:8.0 + drumsergio/genieacs:1.2.13.2

# 2) TLS front-end (keep running in background)
python "<repo>\tls\pass_front.py"    # listens 0.0.0.0:8443 + :9443

# 3) DNS (Method B above)

# 4) Watcher: poll NBI, fire payload, hammer ADB (see §4)
```

Firewall (elevated once):

```
netsh advfirewall firewall add rule name="JioStb-Exploit-TCP" dir=in action=allow protocol=TCP localport=53,8443,7547,7557
netsh advfirewall firewall add rule name="JioStb-Exploit-UDP" dir=in action=allow protocol=UDP localport=53
```

## 3. Stage 1 payload

```powershell
& 'E:\Git\bin\bash.exe' -lc './stage1.sh --tasks-only --stb-ip <STB_IP>'
```

What it queues (applies on next Inform):
- `Device.JioSTB.USB.USBDebugging = true`
- `Device.JioSTB.USB.DebugValidityDate = 2037-01-01`
- `Device.JioSTB.FOTA.Disable = true` (+ downgrade enable)

Running **without** `--tasks-only` additionally provisions the box, disables the TR‑069
client app, and uninstalls ~45 bloatware packages per-user.

## 4. Watcher (automation loop)

```powershell
# poll NBI every 10 s; the moment a device appears → stage1 → adb hammer
while (true) {
  try { $d = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 'http://127.0.0.1:7557/devices/?projection=_id,_lastInform').Content | ConvertFrom-Json } catch { $d = @() }
  if ($d.Count -gt 0) { & 'E:\Git\bin\bash.exe' -lc './stage1.sh --tasks-only --stb-ip <STB_IP>'; break }
  Start-Sleep 10
}
for ($i = 0; $i -lt 90; $i++) {
  $c = adb connect '<STB_IP>:5555' 2>&1
  if ($c -match 'connected') { break }
  Start-Sleep 20
}
```

## 5. Installing apps (incl. "unknown sources")

```powershell
adb connect <STB_IP>:5555
adb -s <STB_IP>:5555 install -r "<path>\app.apk"   # Success = done
```

Verified installs on JMSD200A (32-bit ARM, ABI `armeabi-v7a` — do NOT use arm64 APKs):

| App | Package | Source |
|---|---|---|
| SmartTube 32.71 (armeabi-v7a) | `org.smarttube.stable` | github.com/yuliskov/SmartTube/releases |
| Kartoons | `com.kartoons.app` | obtained APK |

**Direct (non-ADB) installs** — give the receiving app permission to install unknown apps,
then APks can be sent/shared to the box and installed there:

```powershell
adb shell "appops set com.yablio.sendfilestotv REQUEST_INSTALL_PACKAGES allow"   # Send Files to TV
adb shell "settings put global verifier_verify_adb_installs 0"                   # skip Play-Verify for adb installs
```

> Must run **after** the package is installed (appops needs an existing UID; error
> `No UID for <pkg> in user 0` means the app isn't installed yet).

## 6. Recommended APKs (see README for the user-facing table)

- **SmartTube** — YouTube without ads — STB
- **Kartoons** — cartoons for kids — STB
- **NetMirror** — movies/series — STB
- **Send Files to TV** — phone ⇄ box file sharing + direct APK install — STB + phone
- **Tellyscope** — control the box from the phone — **phone only** (companion remote app)

## 7. Real errors encountered (and fixes)

| Error / symptom | Cause | Fix |
|---|---|---|
| Box never appears in GenieACS (0 packets even with DNS 1/2 = PC) | Jio phone hotspot hijacks provisioning through itself (port 7443); static-DNS UI silently reverts | Move topology to **Method B** (PC hotspot). Confirmed working on first Inform. |
| `adb connect` → `unauthorized` | Stale connection after IP churn/host Charlie rotation | `adb kill-server`? Not needed: just re-run `adb connect`; wait for user to accept the on-screen dialog if it appears. |
| `error: device not found` immediately after `connected to x:5555` | Device dropped off the hotspot (ESSID/BSSID flapping, going to sleep) | Keep the box awake; re-run `adb connect`. |
| `docker compose up` → `getting credentials` | `docker-credential-desktop` not on PATH | Prepend Docker's bin folder to `$env:Path` in every shell used. |
| stage1.sh: `python3 not found` | Store stub shadows real python | Install the `~/.local/bin/python3` shim (see §0). |
| Npcap silent install (`/S`) does nothing; service missing | Installer needs an interactive/elevated run on some setups | Run the GUI installer elevated (`Start-Process -Verb RunAs`), user clicks default **"WinPcap API-compatible Mode"** install. Verify: `sc query npcap` → RUNNING. |
| UDP/53 conflicts with ICS DNS proxy | Windows ICS holds `0.0.0.0:53` | Bind dnsmasq **specifically** to `192.168.137.1:53` (see §1, method B). |
| `pktmon` captures / firewall | needs elevation | UAC one-liners via `Start-Process -Verb RunAs`. |
| `appops` → `No UID for ...` | Package not installed on the box | Install the app first, then grant. |
| APKpure `.xapk` app crashes instantly (`Resources$NotFoundException`) | `.xapk` is a split bundle — installing just the base APK misses the config splits | Unzip the xapk and `adb install-multiple` base + `config.en.apk` + density config; **drop any `config.arm64_v8a.apk` on this 32-bit box** or it fails with `INSTALL_FAILED_NO_MATCHING_ABIS`. |
| Factory reset wipes all per-user changes | expected | Re-run the whole unlock after any reset. |

## 8. Stage 2 — do NOT do this blindly

`unlock.sh` (bootloader) rides CVE‑2024‑31317, patched in the **June 2024** ASB. This box
runs patch `2024-06-05` → **the CME will NOT work.** Stage 2 on this build should be
considered unavailable until a downgrade exists. Don't walk a user into a brick.

---

*Maintainer note: this file is intentionally verbose and first-person — it is the
accumulated field notes of getting this to work end-to-end once on real hardware.*
