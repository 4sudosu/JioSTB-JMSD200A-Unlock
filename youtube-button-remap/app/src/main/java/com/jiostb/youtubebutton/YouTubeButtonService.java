package com.jiostb.youtubebutton;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.util.Log;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

/** Remaps Jio remote buttons: YouTube (F10/140, scan 187) -> SmartTube, Netflix (137) -> Kartoons. */
public class YouTubeButtonService extends AccessibilityService {
    private static final String TAG = "YTBtnRemap";

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) { }

    @Override
    public void onInterrupt() { }

    private void launch(String pkg) {
        Intent i = getPackageManager().getLaunchIntentForPackage(pkg);
        if (i != null) { i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); try { startActivity(i); } catch (RuntimeException ignored) {} }
    }

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        int code = event.getKeyCode();
        int scan = event.getScanCode();
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            Log.i(TAG, "key down code=" + code + " name=" + KeyEvent.keyCodeToString(code) + " scan=" + scan);
        }
        // YouTube button: KEYCODE_F10 (140), scan 187 (Linux F17) on Jio BLE remote
        if (code == 140 || code == 187 || code == 188 || scan == 187
                || "KEYCODE_F17".equals(KeyEvent.keyCodeToString(code))) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) { Log.i(TAG, "YouTube -> SmartTube"); launch("org.smarttube.stable"); }
            return true;
        }
        // Netflix button -> Kartoons
        if (code == 137 || "KEYCODE_F7".equals(KeyEvent.keyCodeToString(code))) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) { Log.i(TAG, "Netflix -> Kartoons"); launch("com.kartoons.app"); }
            return true;
        }
        return super.onKeyEvent(event);
    }
}
