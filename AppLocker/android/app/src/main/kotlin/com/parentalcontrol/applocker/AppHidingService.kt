package com.parentalcontrol.applocker

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat

class AppHidingService : Service() {
    
    private val hiddenPackages = mutableSetOf<String>()
    private val devicePolicyManager by lazy {
        getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
    }

    private val adminComponent by lazy {
        android.content.ComponentName(this, AppLockerAdminReceiver::class.java)
    }
    
    companion object {
        private const val NOTIFICATION_ID = 9004
        private const val CHANNEL_ID = "app_hiding_service"
        private const val CHANNEL_NAME = "App Hiding Service"
        
        fun isServiceRunning(context: Context): Boolean {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            for (service in activityManager.getRunningServices(Int.MAX_VALUE)) {
                if (service.service.className == AppHidingService::class.java.name) {
                    return true
                }
            }
            return false
        }
        
        fun startHidingService(context: Context) {
            val intent = Intent(context, AppHidingService::class.java).apply {
                action = "START_SERVICE"
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun hideApp(context: Context, packageName: String) {
            val intent = Intent(context, AppHidingService::class.java).apply {
                action = "HIDE_APP"
                putExtra("packageName", packageName)
            }
            context.startService(intent)
        }
        
        fun unhideApp(context: Context, packageName: String) {
            val intent = Intent(context, AppHidingService::class.java).apply {
                action = "UNHIDE_APP"
                putExtra("packageName", packageName)
            }
            context.startService(intent)
        }
        
        fun syncHiddenApps(context: Context, packages: List<String>) {
            val intent = Intent(context, AppHidingService::class.java).apply {
                action = "SYNC_HIDDEN_APPS"
                putExtra("packages", ArrayList(packages))
            }
            context.startService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        // CRITICAL: must call startForeground immediately in onCreate on Android 12+
        createNotificationChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("App Hiding Active")
            .setContentText("Managing hidden applications")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "START_SERVICE" -> {
                startForegroundNotification()
            }
            "HIDE_APP" -> {
                val packageName = intent.getStringExtra("packageName")
                if (packageName != null) {
                    hideApp(packageName)
                }
            }
            "UNHIDE_APP" -> {
                val packageName = intent.getStringExtra("packageName")
                if (packageName != null) {
                    unhideApp(packageName)
                }
            }
            "SYNC_HIDDEN_APPS" -> {
                val packages = intent.getStringArrayListExtra("packages")
                if (packages != null) {
                    syncHiddenApps(packages)
                }
            }
        }
        
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Manages app hiding functionality"
                setShowBadge(false)
            }
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundNotification() {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("App Hiding Active")
            .setContentText("Managing hidden applications")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun hideApp(packageName: String): Boolean {
        if (hiddenPackages.contains(packageName)) {
            return true // Already hidden
        }
        
        val success = try {
            // FIX: Check if OUR app is the device owner, not the target
            val isOwner = devicePolicyManager.isDeviceOwnerApp(this.packageName) || devicePolicyManager.isProfileOwnerApp(this.packageName)
            if (isOwner) {
                devicePolicyManager.setApplicationHidden(adminComponent, packageName, true)
            } else {
                // Fallback: disable launcher activity
                hideAppLauncher(packageName)
            }
        } catch (e: Exception) {
            println("Failed to hide app via DPM: ${e.message}")
            // Try fallback method
            hideAppLauncher(packageName)
        }
        
        if (success) {
            hiddenPackages.add(packageName)
            println("Successfully hidden app: $packageName")
        }
        
        return success
    }

    private fun unhideApp(packageName: String): Boolean {
        if (!hiddenPackages.contains(packageName)) {
            return true // Already visible
        }
        
        val success = try {
            // FIX: Check if OUR app is the device owner, not the target
            val isOwner = devicePolicyManager.isDeviceOwnerApp(this.packageName) || devicePolicyManager.isProfileOwnerApp(this.packageName)
            if (isOwner) {
                devicePolicyManager.setApplicationHidden(adminComponent, packageName, false)
            } else {
                // Fallback: enable launcher activity
                unhideAppLauncher(packageName)
            }
        } catch (e: Exception) {
            println("Failed to unhide app via DPM: ${e.message}")
            // Try fallback method
            unhideAppLauncher(packageName)
        }
        
        if (success) {
            hiddenPackages.remove(packageName)
            println("Successfully unhidden app: $packageName")
        }
        
        return success
    }

    private fun hideAppLauncher(packageName: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            val component = intent?.component
            if (component != null) {
                packageManager.setComponentEnabledSetting(
                    component,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
                true
            } else {
                false
            }
        } catch (e: Exception) {
            println("Failed to hide app launcher: ${e.message}")
            false
        }
    }

    private fun unhideAppLauncher(packageName: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            val component = intent?.component
            if (component != null) {
                packageManager.setComponentEnabledSetting(
                    component,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )
                true
            } else {
                false
            }
        } catch (e: Exception) {
            println("Failed to unhide app launcher: ${e.message}")
            false
        }
    }

    private fun syncHiddenApps(packages: List<String>) {
        // Unhide apps that are no longer in the hidden list
        val toUnhide = hiddenPackages - packages.toSet()
        toUnhide.forEach { unhideApp(it) }
        
        // Hide apps that should be hidden
        packages.forEach { hideApp(it) }
    }

    private fun isAppHidden(packageName: String): Boolean {
        return try {
            // FIX: Check if OUR app is the device owner, not the target
            val isOwner = devicePolicyManager.isDeviceOwnerApp(this.packageName) || devicePolicyManager.isProfileOwnerApp(this.packageName)
            if (isOwner) {
                devicePolicyManager.isApplicationHidden(adminComponent, packageName)
            } else {
                // Check component enabled state
                val intent = packageManager.getLaunchIntentForPackage(packageName)
                val component = intent?.component
                if (component != null) {
                    val state = packageManager.getComponentEnabledSetting(component)
                    state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED ||
                    state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER
                } else {
                    false
                }
            }
        } catch (e: Exception) {
            println("Failed to check if app is hidden: ${e.message}")
            false
        }
    }

    fun getHiddenApps(): Set<String> {
        return hiddenPackages.toSet()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        // Optionally restore all hidden apps when service is destroyed
        hiddenPackages.forEach { unhideApp(it) }
    }
}
