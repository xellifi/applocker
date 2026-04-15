package com.parentalcontrol.applocker

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * AppLockerAdminReceiver
 *
 * Handles Device Admin activation/deactivation.
 * Uses ADMIN mode (NOT device_owner) for easy uninstall:
 *   Settings → Security → Device Admin Apps → AppLocker → Deactivate
 *
 * TEST: Enable admin via Settings, then lock from parent dashboard
 * TEST: Deactivate admin from Settings → confirm uninstall works
 */
class AppLockerAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        Log.d("AppLocker", "Device Admin enabled")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        Log.d("AppLocker", "Device Admin disabled — app can be uninstalled")
    }

    override fun onPasswordFailed(context: Context, intent: Intent) {
        Log.d("AppLocker", "Password attempt failed")
    }

    override fun onPasswordSucceeded(context: Context, intent: Intent) {
        Log.d("AppLocker", "Password attempt succeeded")
    }
}
