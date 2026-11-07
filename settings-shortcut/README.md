# Android Settings shortcut

Tiny (8 KB) app that puts an **"Android Settings"** icon in the launcher and opens the stock `com.android.tv.settings/.MainSettings` directly — no USB-gallery trick needed.

**Prebuilt APK:** [`../apk/android-settings-shortcut.apk`](../apk/android-settings-shortcut.apk) — install during unlock:

```powershell
adb install apk\android-settings-shortcut.apk
```

**Rebuild:**

```powershell
cd settings-shortcut
.\gradlew.bat :app:assembleRelease
```

Requires Android SDK + JDK 17. No dependencies — plain Java, one activity, ~30 lines.
