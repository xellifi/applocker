package com.parentalcontrol.applocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BootReceiver
 *
 * Restarts the AppLockerBackgroundService after device reboot.
 * This ensures the Firestore lock-state poller continues to run
 * and the lock overlay can be triggered even after a restart.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            
            Log.d("AppLocker", "Boot/update detected — restarting background service")

            // Try FlutterSharedPreferences first, then fall back to local backup
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val localPrefs = context.getSharedPreferences("applocker_local_settings", Context.MODE_PRIVATE)

            val deviceId = flutterPrefs.getString("flutter.deviceId", "")
                ?.takeIf { it.isNotEmpty() }
                ?: localPrefs.getString("device_id", "") ?: ""

            if (deviceId.isEmpty()) {
                Log.d("AppLocker", "No deviceId saved, skipping service start")
                return
            }

            // Also read the saved PIN so overlay shows the correct PIN immediately
            val pin = localPrefs.getString("pin", "1234") ?: "1234"

            val serviceIntent = Intent(context, AppLockerBackgroundService::class.java).apply {
                putExtra("deviceId", deviceId)
                putExtra("pin", pin)
                // Signal that this is a boot-start so the service can
                // immediately restore the lock state from local prefs.
                putExtra("action", "boot")
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
                Log.d("AppLocker", "Background service restarted for deviceId=$deviceId pin=***")
            } catch (e: Exception) {
                Log.e("AppLocker", "Failed to restart service: ${e.message}")
            }
        }
    }
}
