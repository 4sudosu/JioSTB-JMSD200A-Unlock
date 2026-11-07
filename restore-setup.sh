#!/usr/bin/env bash
# Restore this box's setup (apps + settings) over ADB.
# Usage: ./restore-setup.sh [STB_IP[:PORT]] [APK_DIR]
#   STB_IP defaults to 192.168.137.89:5555 (PC hotspot). APK_DIR defaults to ./user-apks
set -u
STB="${1:-192.168.137.89:5555}"
APK_DIR="${2:-$(dirname "$0")/user-apks}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

adb connect "$STB" >/dev/null 2>&1 || true
state=$(adb -s "$STB" get-state 2>/dev/null || echo "missing")
if [ "$state" != "device" ]; then
  echo "ADB not ready for $STB (state=$state). Connect the box and accept 'Allow USB debugging' on TV."
  exit 1
fi
echo "== Restoring setup on $STB =="

echo "[1/4] System settings"
adb -s "$STB" shell settings put global verifier_verify_adb_installs 0
adb -s "$STB" shell settings put secure install_non_market_apps 1
# Remote YouTube button -> SmartTube (Jio premium remote mapping)
RK='[{"applicationName":"Hotstar","keycode":138,"packageName":"in.startv.hotstar"},{"applicationName":"Netflix","keycode":137,"packageName":"com.netflix.ninja"},{"applicationName":"PrimeVideo","keycode":134,"packageName":"com.amazon.amazonvideo.livingroom"},{"applicationName":"SonyLiv","keycode":141,"packageName":"com.jiotv.sonyliv"},{"applicationName":"Zee5","keycode":142,"packageName":"com.zee5.aosp"},{"applicationName":"SmartTube","keycode":140,"packageName":"org.smarttube.stable"}]'
printf '%s' "$RK" | adb -s "$STB" shell "cat > /sdcard/jio_rk.json && settings put global jio_premium_remote_setup_complete \"\$(cat /sdcard/jio_rk.json)\""
echo "  verifier=0, install_non_market_apps=1, YouTube remote button -> SmartTube"

echo "[2/4] Settings shortcut (bundled, REQUIRED)"
adb -s "$STB" install -r "$ROOT/apk/android-settings-shortcut.apk"

install_match() {
  name="$1"; pattern="$2"
  file=$(ls $APK_DIR/$pattern 2>/dev/null | head -1 || true)
  if [ -n "${file:-}" ] && [ -f "$file" ]; then
    echo "  installing $name: $file"
    adb -s "$STB" install -r "$file" || echo "  !! failed: $name"
  else
    echo "  MISSING $name -> put matching file in $APK_DIR ($pattern)"
    return 1
  fi
}

echo "[3/4] User APKs from $APK_DIR (provide your own; see setup-manifest.json)"
mkdir -p "$APK_DIR"
miss=0
install_match "SmartTube (armeabi-v7a)" "*SmartTube*armeabi-v7a*.apk" || miss=1
install_match "Kartoons" "*kartoons*.apk" || miss=1
install_match "NetMirror (Android TV)" "*netmirror*.apk" || miss=1
# SFTV: prefer a plain APK; .xapk needs manual split install (see README)
sftv=$(ls $APK_DIR/*send*files*tv*.apk 2>/dev/null | head -1 || true)
if [ -n "${sftv:-}" ]; then
  install_match "Send Files to TV" "*send*files*tv*.apk" || miss=1
else
  echo "  MISSING Send Files to TV -> $APK_DIR (*send*files*tv*.apk). If you have .xapk, unzip &: adb install-multiple base.apk config.en.apk config.*dpi*.apk (SKIP config.arm64_v8a on 32-bit)"
  miss=1
fi

echo "[4/4] Send Files to TV install permission (direct APK installs on box)"
if adb -s "$STB" shell pm list packages | grep -q com.yablio.sendfilestotv; then
  adb -s "$STB" shell appops set com.yablio.sendfilestotv REQUEST_INSTALL_PACKAGES allow
  echo "  REQUEST_INSTALL_PACKAGES=allow"
else
  echo "  skipped (Send Files to TV not installed)"
fi

echo "== Done =="
adb -s "$STB" shell pm list packages | grep -E 'smarttube|kartoons|netmirror|sendfilestotv|settingshortcut' || true
[ "$miss" -eq 0 ] && echo "All apps restored." || echo "Some APKs missing — add them to $APK_DIR and re-run (safe to re-run)."
echo "Note: Jio launcher home-pin order is not auto-restored (launcher keeps its own config)."
