package com.jiostb.youtubebutton;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.util.Log;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

/** Intercepts the Jio remote's YouTube button (F17, Linux key from BLE keyboard) and launches SmartTube. */
public class YouTubeButtonService extends AccessibilityService {
    private static final String TAG = "YTBtnRemap";

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) { }

    @Override
    public void onInterrupt() { }

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        int code = event.getKeyCode();
        int scan = event.getScanCode();
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            Log.i(TAG, "key down code=" + code + " name=" + KeyEvent.keyCodeToString(code) + " scan=" + scan);
        }
        // Jio BLE remote YouTube button arrives as KEYCODE_F10 (140), scan 187 (Linux F17)
        boolean isYt = (code == 140 || code == 187 || code == 188 || scan == 187
                || "KEYCODE_F17".equals(KeyEvent.keyCodeToString(code)));
        if (isYt) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                Log.i(TAG, "YouTube button -> launching SmartTube");
                Intent i = getPackageManager().getLaunchIntentForPackage("org.smarttube.stable");
                if (i == null) i = new Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://www.youtube.com"));
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                try { startActivity(i); } catch (RuntimeException ignored) { }
            }
            return true;
        }
        return super.onKeyEvent(event);
    }
}
