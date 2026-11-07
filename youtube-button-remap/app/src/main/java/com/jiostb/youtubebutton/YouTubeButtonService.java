package com.jiostb.youtubebutton;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.Intent;
import android.util.Log;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

/** Remaps Jio remote buttons: YouTube (F10/140, scan 187) -> SmartTube, Netflix (137) -> Kartoons. */
public class YouTubeButtonService extends AccessibilityService {
    private static final String TAG = "YTBtnRemap";

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        AccessibilityServiceInfo info = getServiceInfo();
        if (info == null) info = new AccessibilityServiceInfo();
        info.flags |= AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS;
        info.eventTypes = AccessibilityEvent.TYPES_ALL_MASK;
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        setServiceInfo(info);
        Log.i(TAG, "service connected, key filtering enabled");
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) { }

    @Override
    public void onInterrupt() { }

    private void launch(String pkg) {
        try {
            Intent i = getPackageManager().getLaunchIntentForPackage(pkg);
            if (i == null) i = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER).setPackage(pkg);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
            startActivity(i);
        } catch (Exception e) {
            Log.w(TAG, "launch intent failed: " + pkg, e);
        }
        try { // belt-and-suspenders: force via am (helps when startActivity is preempted)
            String[] cmd;
            if ("org.smarttube.stable".equals(pkg)) {
                cmd = new String[]{"am", "start", "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LEANBACK_LAUNCHER", "-n", "org.smarttube.stable/com.liskovsoft.smartyoutubetv2.tv.ui.main.SplashActivity"};
            } else {
                cmd = new String[]{"monkey", "-p", pkg, "-c", "android.intent.category.LAUNCHER", "1"};
            }
            Runtime.getRuntime().exec(cmd);
        } catch (Exception ignored) {}
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
