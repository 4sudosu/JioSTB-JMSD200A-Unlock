package com.jiostb.settingshortcut;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;

/**
 * One purpose: open the stock Android TV Settings (com.android.tv.settings) that Jio's
 * launcher hides behind the USB-gallery trick. Falls back through known alternatives.
 */
public class SettingsShortcutActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        open(
            // stock Android TV Settings (the hidden one)
            new Intent().setClassName("com.android.tv.settings", "com.android.tv.settings.MainSettings"),
            // some builds route it via an action
            new Intent("com.android.tv.settings.MAIN"),
            // last resort: whatever the box wires ACTION_SETTINGS to (may be Jio's settings)
            new Intent(Settings.ACTION_SETTINGS)
        );
        finish();
    }

    private void open(Intent... options) {
        for (Intent i : options) {
            try {
                startActivity(i);
                return;
            } catch (RuntimeException ignored) {
            }
        }
    }
}
