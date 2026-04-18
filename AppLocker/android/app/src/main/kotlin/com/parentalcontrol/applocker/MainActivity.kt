package com.parentalcontrol.applocker

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val LOCK_CHANNEL = "com.parentalcontrol/lock"
    private var channel: MethodChannel? = null
    private val REQ_DEVICE_ADMIN = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOCK_CHANNEL
        )

        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                
                "isPinned" -> {
                    try {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        result.success(am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "startLockTask" -> {
                    try {
                        startLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START_LOCK_TASK_FAILED", e.message, null)
                    }
                }

                "stopLockTask" -> {
                    try {
                        stopLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_LOCK_TASK_FAILED", e.message, null)
                    }
                }

                "openSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_SETTINGS_FAILED", e.message, null)
                    }
                }

                "requestOverlayPermission" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OVERLAY_PERM_FAILED", e.message, null)
                    }
                }

                "requestAdminPermission" -> {
                    try {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
                        val componentName = android.content.ComponentName(this, AppLockerAdminReceiver::class.java)
                        if (dpm.isAdminActive(componentName)) {
                            // Already active — nothing to do
                            result.success(true)
                        } else {
                            val intent = Intent(android.app.admin.DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                            intent.putExtra(android.app.admin.DevicePolicyManager.EXTRA_DEVICE_ADMIN, componentName)
                            intent.putExtra(
                                android.app.admin.DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                "AppLocker needs Device Admin to lock the screen when activated by parent."
                            )
                            // Do NOT set FLAG_ACTIVITY_NEW_TASK — we're already in an Activity
                            // and that flag prevents the system dialog from showing properly.
                            startActivityForResult(intent, REQ_DEVICE_ADMIN)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        // Last resort: open Security settings so user can enable manually
                        try {
                            val fallback = Intent(Settings.ACTION_SECURITY_SETTINGS)
                            startActivity(fallback)
                            result.success(false)
                        } catch (e2: Exception) {
                            result.error("ADMIN_PERM_FAILED", e.message, null)
                        }
                    }
                }

                "isAdminActive" -> {
                    try {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
                        val componentName = android.content.ComponentName(
                            this,
                            AppLockerAdminReceiver::class.java
                        )
                        result.success(dpm.isAdminActive(componentName))
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "hasOverlayPermission" -> {
                    result.success(Settings.canDrawOverlays(this))
                }

                "hasUsagePermission" -> {
                    val appOps = getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
                    val mode = appOps.checkOpNoThrow(
                        android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                        android.os.Process.myUid(), packageName
                    )
                    result.success(mode == android.app.AppOpsManager.MODE_ALLOWED)
                }

                "requestUsagePermission" -> {
                    try {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("USAGE_PERM_FAILED", e.message, null)
                    }
                }

                "getForegroundApp" -> {
                    try {
                        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
                        val time = System.currentTimeMillis()
                        val events = usm.queryEvents(time - 1000 * 60, time)
                        val event = android.app.usage.UsageEvents.Event()
                        var lastPackage: String? = null
                        
                        while (events.hasNextEvent()) {
                            events.getNextEvent(event)
                            if (event.eventType == android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND) {
                                lastPackage = event.packageName
                            }
                        }
                        result.success(lastPackage)
                    } catch (e: Exception) {
                        result.error("GET_FOREGROUND_FAILED", e.message, null)
                    }
                }

                "setApplicationHidden" -> {
                    try {
                        val pkg = call.argument<String>("packageName")
                        val hidden = call.argument<Boolean>("hidden") ?: true
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
                        val componentName = android.content.ComponentName(this, AppLockerAdminReceiver::class.java)
                        
                        if (pkg != null) {
                            var success = false
                            // FIX: Profile Owner AND Device Owner can call setApplicationHidden
                            val isOwner = dpm.isDeviceOwnerApp(packageName) || dpm.isProfileOwnerApp(packageName)
                            try {
                                if (isOwner) {
                                    success = dpm.setApplicationHidden(componentName, pkg, hidden)
                                }
                            } catch (e: Exception) {
                                println("DPM hide failed: ${e.message}")
                            }
                            result.success(success)
                        } else {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                        }
                    } catch (e: Exception) {
                        result.error("SET_HIDDEN_FAILED", e.message, null)
                    }
                }

                "unhideAllPkgs" -> {
                    // FIX: Use DPM.setApplicationHidden(false) for Profile Owner
                    // which is the actual mechanism that hid the apps
                    try {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
                        val componentName = android.content.ComponentName(this, AppLockerAdminReceiver::class.java)
                        val isOwner = dpm.isDeviceOwnerApp(packageName) || dpm.isProfileOwnerApp(packageName)
                        if (!isOwner) {
                            result.error("NOT_OWNER", "Not device or profile owner", null)
                            return@setMethodCallHandler
                        }
                        val pm = packageManager
                        var count = 0
                        // getInstalledPackages with MATCH_UNINSTALLED_PACKAGES returns even DPM-hidden apps
                        val allPackages = pm.getInstalledPackages(PackageManager.MATCH_UNINSTALLED_PACKAGES)
                        for (pkgInfo in allPackages) {
                            val pkg = pkgInfo.packageName
                            if (pkg == packageName) continue
                            try {
                                if (dpm.isApplicationHidden(componentName, pkg)) {
                                    dpm.setApplicationHidden(componentName, pkg, false)
                                    count++
                                }
                            } catch (_: Exception) {}
                        }
                        result.success(count)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }

                "bringToForeground" -> {
                    try {
                        val intent = Intent(this@MainActivity, MainActivity::class.java)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BRING_TO_FOREGROUND_FAILED", e.message, null)
                    }
                }

                "goHome" -> {
                    try {
                        val intent = Intent(Intent.ACTION_MAIN)
                        intent.addCategory(Intent.CATEGORY_HOME)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("GOHOME_FAILED", e.message, null)
                    }
                }

                // ═══════════════════════════════════════════════════════
                // NATIVE OVERLAY CONTROL — The key methods for system overlay
                // ═══════════════════════════════════════════════════════

                "showNativeOverlay" -> {
                    try {
                        val pin = call.argument<String>("pin") ?: "1234"
                        val devId = call.argument<String>("deviceId") ?: ""
                        val profileImageUrl = call.argument<String>("profileImageUrl") ?: ""

                        // Persist these settings so the overlay can read them on restart
                        val prefs = getSharedPreferences("applocker_local_settings", android.content.Context.MODE_PRIVATE)
                        prefs.edit()
                            .putString("deviceId", devId)
                            .putString("pin", pin)
                            .putString("profileImageUrl", profileImageUrl)
                            .apply()
                        
                        if (!Settings.canDrawOverlays(this)) {
                            // No overlay permission — request it
                            val permIntent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            permIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(permIntent)
                            result.error("NO_OVERLAY_PERMISSION", "SYSTEM_ALERT_WINDOW not granted", null)
                            return@setMethodCallHandler
                        }

                        val intent = Intent(this, LockOverlayService::class.java).apply {
                            putExtra("action", "show")
                            putExtra("pin", pin)
                            putExtra("deviceId", devId)
                            putExtra("profileImageUrl", profileImageUrl)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHOW_OVERLAY_FAILED", e.message, null)
                    }
                }

                "hideNativeOverlay" -> {
                    try {
                        val intent = Intent(this, LockOverlayService::class.java).apply {
                            putExtra("action", "hide")
                        }
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("HIDE_OVERLAY_FAILED", e.message, null)
                    }
                }

                "isNativeOverlayShowing" -> {
                    result.success(LockOverlayService.isShowing)
                }

                // Start the background service with Firestore polling
                "startBackgroundService" -> {
                    try {
                        val devId = call.argument<String>("deviceId") ?: ""
                        val pin = call.argument<String>("pin") ?: "1234"
                        
                        val intent = Intent(this, AppLockerBackgroundService::class.java).apply {
                            putExtra("deviceId", devId)
                            putExtra("pin", pin)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START_BG_SERVICE_FAILED", e.message, null)
                    }
                }

                "requestUsageStatsPermission" -> {
                    try {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("USAGE_STATS_PERMISSION_FAILED", e.message, null)
                    }
                }

                "getBlockedPackage" -> {
                    try {
                        val blockedPackage = intent?.getStringExtra("blockedPackage")
                        result.success(blockedPackage)
                    } catch (e: Exception) {
                        result.error("GET_BLOCKED_PACKAGE_FAILED", e.message, null)
                    }
                }

                "clearBlockedPackage" -> {
                    try {
                        intent?.removeExtra("blockedPackage")
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLEAR_BLOCKED_PACKAGE_FAILED", e.message, null)
                    }
                }

                "syncBlockedApps" -> {
                    val apps = call.argument<ArrayList<String>>("blockedApps")
                    val mode = call.argument<String>("controlMode")
                    val temps = call.argument<HashMap<String, Long>>("tempAccess")
                    // BUGFIX: also forward appSchedules so the background service
                    // immediately applies scheduled blocking without waiting for
                    // the next Firestore poll (which can take up to 10 seconds).
                    @Suppress("UNCHECKED_CAST")
                    val appSchedules = call.argument<HashMap<String, Any>>("appSchedules")
                    
                    val intent = Intent(this, AppLockerBackgroundService::class.java)
                    intent.putStringArrayListExtra("blockedApps", apps)
                    intent.putExtra("controlMode", mode)
                    intent.putExtra("tempAccess", temps)
                    if (appSchedules != null) {
                        // Use HashMap (Serializable) for nested maps so Intent extras survive
                        val serializable = HashMap<String, HashMap<String, Any>>()
                        for ((key, value) in appSchedules) {
                            if (value is Map<*, *>) {
                                @Suppress("UNCHECKED_CAST")
                                serializable[key] = HashMap(value as Map<String, Any>)
                            }
                        }
                        intent.putExtra("appSchedules", serializable)
                    }
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }

                "stopAppLockerService" -> {
                    val intent = Intent(this, AppLockerBackgroundService::class.java)
                    stopService(intent)
                    result.success(true)
                }

                "listLaunchableApps" -> {
                    try {
                        val pm = packageManager
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
                        val adminComponent = android.content.ComponentName(this, AppLockerAdminReceiver::class.java)
                        val isOwner = dpm.isDeviceOwnerApp(packageName) || dpm.isProfileOwnerApp(packageName)
                        val out = ArrayList<Map<String, String>>()
                        val seen = HashSet<String>()

                        // MATCH_UNINSTALLED_PACKAGES returns even DPM-hidden apps
                        val allApps = pm.getInstalledApplications(
                            PackageManager.MATCH_UNINSTALLED_PACKAGES or PackageManager.MATCH_DISABLED_COMPONENTS)
                        for (appInfo in allApps) {
                            val pkg = appInfo.packageName
                            if (pkg == packageName) continue
                            if (!seen.add(pkg)) continue

                            // Check if app is hidden via DPM — if so still include it
                            val isHiddenByDpm = isOwner && try {
                                dpm.isApplicationHidden(adminComponent, pkg)
                            } catch (_: Exception) { false }

                            // Include if launchable OR DPM-hidden (means it WAS launchable)
                            val launchIntent = pm.getLaunchIntentForPackage(pkg)
                            if (launchIntent != null || isHiddenByDpm) {
                                val label = try {
                                    pm.getApplicationLabel(appInfo).toString()
                                } catch (_: Exception) { pkg }
                                out.add(mapOf("packageName" to pkg, "name" to label))
                            }
                        }
                        result.success(out)
                    } catch (e: Exception) {
                        result.error("LIST_APPS_FAILED", e.message, null)
                    }
                }



                "getAppIcon" -> {
                    try {
                        val pkg = call.argument<String>("packageName")
                        if (pkg != null) {
                            val pm = packageManager
                            val icon = pm.getApplicationIcon(pkg)
                            val bitmap = if (icon is android.graphics.drawable.BitmapDrawable) {
                                icon.bitmap
                            } else {
                                val width = if (icon.intrinsicWidth > 0) icon.intrinsicWidth else 128
                                val height = if (icon.intrinsicHeight > 0) icon.intrinsicHeight else 128
                                val b = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
                                val canvas = android.graphics.Canvas(b)
                                icon.setBounds(0, 0, canvas.width, canvas.height)
                                icon.draw(canvas)
                                b
                            }
                            val scaled = android.graphics.Bitmap.createScaledBitmap(bitmap, 96, 96, true)
                            val stream = java.io.ByteArrayOutputStream()
                            scaled.compress(android.graphics.Bitmap.CompressFormat.PNG, 80, stream)
                            result.success(stream.toByteArray())
                        } else {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                        }
                    } catch (e: Exception) {
                        result.error("GET_ICON_FAILED", e.message, null)
                    }
                }

                "getAppName" -> {
                    try {
                        val pkg = call.argument<String>("packageName")
                        if (pkg != null) {
                            val pm = packageManager
                            val info = pm.getApplicationInfo(pkg, 0)
                            val name = pm.getApplicationLabel(info).toString()
                            result.success(name)
                        } else {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                        }
                    } catch (e: Exception) {
                        result.success(call.argument<String>("packageName") ?: "Unknown App")
                    }
                }

                "isDeviceOwner" -> {
                    try {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
                        result.success(dpm.isDeviceOwnerApp(packageName))
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                // Basic Mode - App Overlay Service
                "showAppOverlay" -> {
                    try {
                        val packageName = call.argument<String>("packageName")
                        if (packageName != null) {
                            AppOverlayService.startOverlayService(this, packageName)
                            result.success(true)
                        } else {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                        }
                    } catch (e: Exception) {
                        result.error("SHOW_OVERLAY_FAILED", e.message, null)
                    }
                }

                "hideAppOverlay" -> {
                    try {
                        AppOverlayService.stopOverlayService(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("HIDE_OVERLAY_FAILED", e.message, null)
                    }
                }

                "isOverlayServiceRunning" -> {
                    try {
                        result.success(AppOverlayService.isServiceRunning(this))
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                // Advanced Mode - App Hiding Service
                "startHidingService" -> {
                    try {
                        AppHidingService.startHidingService(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START_HIDING_FAILED", e.message, null)
                    }
                }

                "hideAppPackage" -> {
                    try {
                        val packageName = call.argument<String>("packageName")
                        if (packageName != null) {
                            AppHidingService.hideApp(this, packageName)
                            result.success(true)
                        } else {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                        }
                    } catch (e: Exception) {
                        result.error("HIDE_APP_FAILED", e.message, null)
                    }
                }

                "unhideAppPackage" -> {
                    try {
                        val packageName = call.argument<String>("packageName")
                        if (packageName != null) {
                            AppHidingService.unhideApp(this, packageName)
                            result.success(true)
                        } else {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                        }
                    } catch (e: Exception) {
                        result.error("UNHIDE_APP_FAILED", e.message, null)
                    }
                }

                "syncHiddenApps" -> {
                    try {
                        val packages = call.argument<List<String>>("packages")
                        if (packages != null) {
                            AppHidingService.syncHiddenApps(this, packages)
                            result.success(true)
                        } else {
                            result.error("INVALID_PACKAGES", "Packages list is null", null)
                        }
                    } catch (e: Exception) {
                        result.error("SYNC_HIDDEN_FAILED", e.message, null)
                    }
                }

                "isHidingServiceRunning" -> {
                    try {
                        result.success(AppHidingService.isServiceRunning(this))
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "hasAccessibilityPermission" -> {
                    try {
                        val am = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
                        val enabledServices = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                        val serviceName = "$packageName/${MonitoringService::class.java.canonicalName}"
                        val enabled = enabledServices?.contains(serviceName) == true
                        result.success(enabled)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "requestAccessibilityPermission" -> {
                    try {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ACCESSIBILITY_PERM_FAILED", e.message, null)
                    }
                }

                "hasNotificationPermission" -> {
                    try {
                        val enabledListeners = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                        val enabled = enabledListeners?.contains(packageName) == true
                        result.success(enabled)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "requestNotificationPermission" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        } else {
                            Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                        }
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_PERM_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val blockedPackage = intent?.getStringExtra("blockedPackage")
        if (blockedPackage != null) {
            channel?.invokeMethod("onAppBlocked", mapOf("packageName" to blockedPackage))
            intent.removeExtra("blockedPackage")
        }
    }
}
