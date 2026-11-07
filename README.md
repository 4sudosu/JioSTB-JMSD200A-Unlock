# 🔓 JioSTB (JMSD200A) Unlock

> **Unlock the Jio Set‑Top Box (model JMSD200A) — enable ADB, disable firmware updates, kill boot ads, sideload your own apps.**
> Based on the [Housekeeping‑PoC](https://github.com/JFC-Group/Housekeeping-PoC) exploit — see [Credits](#-credits).

![Platform](https://img.shields.io/badge/platform-Windows-blue) ![Android](https://img.shields.io/badge/Android%20TV-11-orange) ![Firmware](https://img.shields.io/b/firmware/patch%202024--06--05-green) ![License](https://img.shields.io/badge/license-Apache%202.0-red)

## ⚡ Fastest way (same-model STB: JMSD200A)

> **Clone this repo and unlock the SetupBox — that’s it.** (You/your AI runs one script; you do 3 manual steps: PC hotspot on, connect STB, reboot STB.)

```powershell
git clone https://github.com/4sudosu/JioSTB-JMSD200A-Unlock.git
cd JioSTB-JMSD200A-Unlock
.\unlock-setupbox.ps1
```

**Tell your AI:** *"Clone https://github.com/4sudosu/JioSTB-JMSD200A-Unlock and unlock my JMSD200A SetupBox (use unlock-setupbox.ps1, Method B PC hotspot). Walk me through the manual steps."*

**Prereqs (install once):** [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/) (running), [Python 3](https://www.python.org/downloads/), [Git for Windows](https://gitforwindows.org/), [ADB platform-tools](https://developer.android.com/tools/releases/platform-tools) on PATH. `python -m pip install pycryptodome`

What the script automates: GenieACS + TLS front-end + DNS spoof (Method B, `192.168.137.1`), watches for the STB, runs Stage 1 payload, polls ADB, and applies the **default setup** (Settings shortcut, remote button remap YouTube→SmartTube/Netflix→Kartoons, required flags, hardening — see `setup-manifest.json`). What **you** do when prompted: phone hotspot OFF → PC Mobile Hotspot ON → connect STB to PC hotspot (DHCP) → reboot STB → accept "Allow USB debugging" on TV if shown. After unlock (optional): `.\restore-setup.ps1 -Stb <STB_IP>:5555` installs the full app set from `user-apks/`. Full details below.

---

## ⚠️ Read this first

- Use **only on hardware you own**. This changes provisioning state on the box and **likely violates Jio's terms of service**.
- **Stage 1** (ADB enable) is safe and reversible with a factory reset.
- **Stage 2** (bootloader unlock) can **brick your box** — read [`Housekeeping-UBoot.md`](Housekeeping-UBoot.md) before even thinking about it.
- Tested on **JMSD200A**, Android 11, security patch **2024‑06‑05**.

## 🧠 How it works

Jio removed the ADB/debugging toggles from the box's firmware. ADB is controlled by a **TR‑069 provisioning flag** — the box periodically phones home to `https://acs.oss.jio.com:8443` and asks Jio's server "is USB debugging allowed?".

This repo makes your own PC **become that server**:

```
JioSTB ──HTTPS :8443──▶ pass_front.py (TLS, on your PC) ──▶ GenieACS (Docker) ──▶ payload:
                                                                          ✔ USBDebugging = true
                                                                          ✔ DebugValidityDate = 2037
                                                                          ✔ FOTA updates = off
                                                                          ✔ boot ads = off
```

Two conditions make the box talk to your PC instead of Jio:

1. **DNS** — `acs.oss.jio.com` must resolve to your PC's IP
2. **Reboot** — the box contacts the "ACS" right after every boot

## 🚀 Quick start

### Pre-requisites (PC side)

| Tool | Why | Install |
|---|---|---|
| Docker Desktop | runs GenieACS + Mongo | [docker.com](https://docs.docker.com/desktop/setup/install/windows-install/) |
| Python 3 | TLS front-end + JSON handling | [python.org](https://www.python.org/downloads/) |
| Git for Windows | bash to run the scripts | [gitforwindows.org](https://gitforwindows.org/) |
| ADB (platform-tools) | talk to the box once ADB opens | [Android tools](https://developer.android.com/tools/releases/platform-tools) |
| Npcap | only needed for `mitm.py` (plan‑B) | [npcap.com](https://npcap.com/#download) |

Python deps: `python -m pip install pycryptodome scapy`

### 1. Bring the lab up

```bash
cd tls
docker compose up -d          # GenieACS + MongoDB
python pass_front.py          # TLS front-end on :8443/:9443 (leave it running)
```

### 2. Make the box use your PC's DNS

Two ways that work. Pick per your network:

#### Method A — home router (the classic way)

In the box's **hidden stock settings** (open via the USB trick: *My Music → Settings → Eject USB → Internal Storage → Apps → Settings gear*):

- Network → your Wi‑Fi → **Advanced IP settings** → DHCP → **Static**
- Keep IP/Gateway/Mask as they were
- Set **DNS 1 and DNS 2 = your PC's IP**

On your PC run a DNS server that answers `acs.oss.jio.com` with the PC's own IP — the included [`tls/dns/dnsmasq.conf`](tls/dns/dnsmasq.conf) + a dnsmasq container (or Technitium) does exactly that:

```bash
docker run -d --name jio-dns --restart unless-stopped \
  -p <PC_IP>:53:53/udp -p <PC_IP>:53:53/tcp \
  -v "$PWD/tls/dns/dnsmasq.conf:/etc/dnsmasq.conf:ro" jpillora/dnsmasq
```

(edit the conf to point `jio.com` at your PC's IP)

#### Method B — no router at all: Windows Mobile Hotspot ✅ *verified working on JMSD200A*

Wasn't your home internet available? Make **your PC the router**:

1. Phone hotspot **OFF** (or the STB will run back to it — a Jio phone's hotspot hijacks the STB's provisioning through the phone itself, which breaks the redirect)
2. **PC:** *Settings → Network & Internet → Mobile hotspot* → ON
3. **STB:** connect to the PC's hotspot SSID — leave everything on **DHCP**, don't touch static DNS
4. Windows ICS gives the STB `192.168.137.x` and the PC (`192.168.137.1`) is its DNS server automatically
5. Answer `jio.com` names with the PC's IP — bind your dnsmasq to the ICS address (a wildcard-bound Windows DNS proxy already holds `:53`, but Windows grants our *specific* binding priority):

```bash
docker run -d --name jio-dns --restart unless-stopped \
  -p 192.168.137.1:53:53/udp -p 192.168.137.1:53:53/tcp \
  -v "$PWD/tls/dns/dnsmasq.conf:/etc/dnsmasq.conf:ro" jpillora/dnsmasq
```

```
# tls/dns/dnsmasq.conf
address=/jio.com/192.168.137.1     # the PC (hotspot gateway)
server=10.124.65.73                # upstream DNS (phone/hotspot) — anything works
```

### 3. Fire the payload

```bash
./stage1.sh --tasks-only --stb-ip <STB_IP>
```

No device yet? **Reboot the STB** — it phones home to your fake ACS within ~6 minutes of boot, and the moment it shows up the payload queues. It applies on the next Inform (~6 min later). Then:

```bash
adb connect <STB_IP>:5555
adb devices        # → "192.168.137.x:5555   device"
```

A "**Allow USB debugging**" dialog may appear on the TV screen — accept it if it does. On JMSD200A it often auto-authorizes.

### 4. Install your apps + the settings shortcut

```bash
adb install "C:\path\to\your_app.apk"
```

And immediately after unlocking, install the **stock Android Settings shortcut** — Jio's firmware hides the real Android (TV) Settings menu behind a fiddly USB-gallery trick, so this tiny app puts a working **"Settings"** icon in the launcher:

```bash
adb install "apk\android-settings-shortcut.apk"     # prebuilt, v1.3
```

Verified working on JMSD200A — opens `com.android.tv.settings/.MainSettings` directly (Network, Apps, Display, Developer options…). One tap, no USB trick. Source: [`settings-shortcut/`](settings-shortcut).

> ✅ **Treat this as part of the unlock.** Without it you'll be doing the "My Music → Settings → Eject USB → Internal storage → Apps → settings gear" dance every time you need real settings.

> ℹ️ **Installing APKs on this firmware:** tap-to-open an `.apk` often shows “No app found” (the stock installer doesn’t handle the file `VIEW` intent). Reliable options: **ADB** (`adb install`), **Send Files to TV** from phone, or **MT Manager/SAI** using their *own* file picker (session install). `unlock/restore` re-enables the system package installer to help session prompts.

## 🔁 Restore this exact setup (one command)

Once ADB is connected (`adb connect <STB_IP>:5555` → `device`), this repo restores the **same default setup as this box** — applied by `unlock-setupbox.ps1` and `restore-setup.ps1/.sh`: SmartTube, Kartoons, NetMirror Android TV, Send Files to TV + install permission, Settings shortcut v1.3, **remote button remap: YouTube→SmartTube, Netflix→Kartoons** (accessibility), required system flags, and hardening (disables `com.jio.store`, `com.jio.appoptimizer`, `com.jio.backgroundscheduler`, uninstalls/disables stock `com.jio.yt` for user 0, re-enables package installer). Reversible/idempotent.

**Windows (PowerShell):**
```powershell
.\restore-setup.ps1 -Stb 192.168.137.89:5555
```
**Git Bash:**
```bash
./restore-setup.sh 192.168.137.89:5555
```

Put any APKs you provide yourself into `user-apks/` (gitignored). The script installs what's there and tells you what's missing — safe to re-run. Exact target state + download hints: [`setup-manifest.json`](setup-manifest.json). Third-party APKs are **not** bundled; the prebuilt Settings shortcut is (`apk/android-settings-shortcut.apk`).

**Tell your AI (copy-paste):** *"In this repo, run restore-setup for my Jio STB at `<STB_IP>:5555`. Apply settings from setup-manifest.json, install apk/android-settings-shortcut.apk, install any matching APKs from user-apks/, and grant Send Files to TV REQUEST_INSTALL_PACKAGES if present. Show what's missing."*

> Note: Jio launcher home-screen pin order isn't auto-restored (the launcher keeps its own config). Factory reset wipes per-user state — re-run after reset. Hardening uses `pm disable-user`/uninstall-for-user and is reversible (`pm enable <pkg>`).

## 📲 Recommended APKs

Apps that work well on this box (`armeabi-v7a` — always pick the **32-bit ARM** build when an app offers multiple APKs):

| App | Purpose | Install where | Where to get it |
|---|---|---|---|
| **SmartTube** | YouTube with **no ads** + background play + SponsorBlock. **Remote YouTube button launches SmartTube** (applied by `unlock-setupbox.ps1` / `restore-setup.ps1`) — keep stock YouTube (`com.jio.yt` / `com.google.android.youtube.tv`) uninstalled. | STB | [github.com/yuliskov/SmartTube/releases](https://github.com/yuliskov/SmartTube/releases) → pick `armeabi-v7a` |
| **NetMirror** | Latest movies & web series | STB | pick the **Android TV** build (not phone/PC/FireStick/Smart TV). Get it from a source you trust. |
| **Kartoons** | Cartoons for kids | STB | search "Kartoons APK" — get it from a source you trust |
| **Send Files to TV** | Phone ⇄ TV file sharing over Wi‑Fi, **and** direct APK installs on the box (see below) | STB **and** phone | Play Store on phone; on the box install `com.yablio.sendfilestotv`. If you have an `.xapk`, unzip & `adb install-multiple` base + `config.en` + density split — **skip `config.arm64_v8a`** on this 32-bit box or it crashes/mis-installs. |
| **Tellyscope** | Control the STB from your phone (remote) | **Phone only** — NOT on the STB | search "Tellyscope APK" — get it from a source you trust |
| **Key Mapper** | Remap remote/buttons, launch actions/apps (FOSS) | STB / Android TV | Plain **`.apk`**: [github.com/keymapperorg/KeyMapper/releases](https://github.com/keymapperorg/KeyMapper/releases) (e.g. `keymapper-*-foss.apk`) |

Install via ADB:

```bash
adb connect <STB_IP>:5555
adb -s <STB_IP>:5555 install -r "path\to\app.apk"
```

### Install unknown apps directly on the box (no PC needed afterwards)

After you install **Send Files to TV** on the box, grant it the install permission — then any APK you send from your phone can be installed right on the TV:

```bash
adb -s <STB_IP>:5555 install -r "path\to\SendFilesToTV.apk"        # install first
adb -s <STB_IP>:5555 shell "appops set com.yablio.sendfilestotv REQUEST_INSTALL_PACKAGES allow"
adb -s <STB_IP>:5555 shell "settings put global verifier_verify_adb_installs 0"
adb -s <STB_IP>:5555 shell "settings put secure install_non_market_apps 1"
```

From then on: share any APK from your phone → *Send Files to TV* → the box receives it → Android asks "install unknown app?" → allow → done. No ADB needed for future installs.

> ⚠️ The `appops` grant **must run after** Send Files to TV is installed — it fails with `No UID for com.yablio.sendfilestotv in user 0` otherwise.


### 5. Plan‑B when DNS just won't take (advanced)

If the box stubbornly ignores its DNS settings (this firmware's static‑IP screen is flaky and Jio's DNS interception rules hit them), [`mitm.py`](mitm.py) intercepts at the network layer instead:

```bash
python mitm.py            # ARP-poisons the gateway +forwards all traffic, and
                          # answers every jio.com DNS query with your PC's IP
# Ctrl+C exits and restores the box's ARP table
```

Needs Npcap + `scapy`. Detects your Wi‑Fi adapter automatically (edit `PC_IP`/`BOX_IP`/`GW_IP` at the top for your subnet).

Want the full field-notes — every error we hit, exact Windows quirks, and the automation watcher loops? See **[AI.md](AI.md)** — the operations manual written for AI agents (and humans who like the whole story).

### 6. What else you get (Stage 1 post‑setup)

`./stage1.sh` without `--tasks-only` also:

- provisions the device + enables the Developer Options flags
- disables the TR‑069 client so the box stops phoning the real Jio server
- uninstalls ~45 Jio bloatware packages (per‑user only — factory reset reverses it)
- removes the Jio launcher *after* suggesting you install a replacement first (it crash‑loops without one!)

## 📁 What each file is

| File | What it does |
|---|---|
| `stage1.sh` | **The main script.** Finds your box in fake-ACS, queues TR‑069 tasks (USB debug on, FOTA off, downgrade enable), then optionally connects ADB and uninstalls Jio bloatware. Run with `--tasks-only` to just queue the payload, `--list-devices` to see the box, `--stb-ip` to skip discovery. |
| `unlock-setupbox.ps1` | **One-command unlock (Windows).** Brings up GenieACS + `pass_front` + dnsmasq (Method B), watches for the STB, runs Stage 1, polls ADB, applies defaults (Settings shortcut + YouTube→SmartTube remap, basic flags). Use this for "clone & unlock SetupBox". |
| `tls/pass_front.py` | TLS front-end. Terminates the box's HTTPS on `:8443`/`:9443` with the RILROOTCA chain, handles session-cookie routing and the Jio "network check" gate spoof, then proxies into GenieACS. Start it before running stage1. |
| `tls/docker-compose.yml` | GenieACS (open-source TR‑069/CWMP ACS) + MongoDB. Ports: 7547 CWMP, 7557 REST API (NBI), 3000 web UI (admin/admin). |
| `tls/acs*.pem`, `rilrootca.pem`, … | The Jio-style TLS cert chain pass_front.py needs so the box's TLS handshake doesn't fail. |
| `tls/dns/dnsmasq.conf` | Drop-in dnsmasq config: answers `*.jio.com` with your PC, forwards everything else upstream. The one DNS change the box needs. |
| `mitm.py` | Plan‑B. ARP-poisons the box's gateway entry, relays its traffic to the real gateway, and forges DNS replies for any `jio.com` query. DNS-settings-proof. |
| `unlock.sh` | ⚠️ **Stage 2 — bootloader unlock** via CVE‑2024‑31317 + Amlogic `setBootenv`. Can brick your box; read [`Housekeeping-UBoot.md`](Housekeeping-UBoot.md) first. |
| `apk/android-settings-shortcut.apk` | **Prebuilt (8 KB)** "Settings" icon — opens stock `com.android.tv.settings` (no USB-gallery trick). Installed by default. |
| `settings-shortcut/` | Source. `gradlew :app:assembleRelease`. |
| `apk/youtube-button-remap.apk` | **Prebuilt** remap (accessibility service) — remote **YouTube** (KEYCODE_F10/140, scan 187) → **SmartTube**, **Netflix** (key 137) → **Kartoons**. Installed + enabled by default. |
| `youtube-button-remap/` | Source. `gradlew :app:assembleRelease`. |
| `restore-setup.ps1` / `restore-setup.sh` | **One-command restore** of this box's setup: system flags, bundled Settings shortcut + YouTube→SmartTube remap (enabled), installs matching APKs from `user-apks/`, grants Send Files to TV install permission. Safe to re-run. |
| `setup-manifest.json` | Target state for restore (apps, packages, required settings, APK name patterns/sources). |
| `user-apks/` (gitignored) | Drop your own `armeabi-v7a` APKs here for restore (not committed). |
| `pull_boot.sh` | Extracts `boot.img` for a Magisk patch (Stage 2 continuation). |
| `rootshell2.jar`, `bootenv.jar` | Helper payloads stage 2 pushes to the box (root shell + U‑Boot env writer). |
| `src/` | PoC source (BootEnv/binder helpers) for the curious. |
| `Housekeeping-SDK.md`, `Housekeeping-UBoot.md` | The original research docs from the Housekeeping‑PoC authors. **Read before Stage 2.** |

## 🧯 Troubleshooting

| Symptom | Fix |
|---|---|
| Box never shows in `--list-devices` | DNS not actually reaching the PC. Check `docker logs jio-dns` — you should see queries. No queries = box is on a different network/using another resolver. Prefer **Method B** (PC hotspot) — least frictions. |
| `adb connect` times out after payload | The task applies on the next Inform — wait a full 6 min cycle, or reboot the box again. Then reconnect. |
| ADB shows `offline`/`unauthorized` | An "Allow USB debugging?" dialog may be waiting on the TV screen. Accept it. |
| Wi‑Fi won't connect after static changes | Forget the network on the box and reconnect — this firmware silently reverts/corrupts static entries (its Settings UI is janky). |
| Firewall blocks the box | Allow inbound TCP 53/8443/7547/7557 (and UDP 53) in Windows Defender. |
| The box reboot-loops after a bad run | Factory reset (Settings or the recessed reset button) puts it back to stock — Stage 1 changes are per-user. |

## 🙏 Credits

This repo is a wrapper/documentation layer. The actual research and tooling belong to the **Housekeeping‑PoC** authors — large part hack work:

- **[JFC-Group / Housekeeping-PoC](https://github.com/JFC-Group/Housekeeping-PoC)** — original exploit ([Apache 2.0](LICENSE))
- **ak_0o7** and **Sandip Bhadoriya** — the ACS attack script
- **Otus9051** — consolidation, reverse engineering, stage‑2 unlock
- **Bihaan Sen** — vulnerability research
- **[Anish240567 / sideload-jiostb-tutorial](https://github.com/Anish240567/sideload-jiostb-tutorial)** and **mohitnirmal/jiostb** — Windows how-to writeups

Please **don't sell** exploits based on this work. These projects exist so dead e-waste boxes get a second life instead of becoming landfill.

## 📜 License

Apache 2.0, same as the upstream project. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
