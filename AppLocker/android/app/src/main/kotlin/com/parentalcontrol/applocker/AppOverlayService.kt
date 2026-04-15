package com.parentalcontrol.applocker

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.*
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat

class AppOverlayService : Service() {
    
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var currentRestrictedPackage: String? = null
    
    companion object {
        private const val NOTIFICATION_ID = 9003
        private const val CHANNEL_ID = "app_overlay_service"
        private const val CHANNEL_NAME = "App Overlay Service"
        
        fun isServiceRunning(context: Context): Boolean {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            for (service in activityManager.getRunningServices(Int.MAX_VALUE)) {
                if (service.service.className == AppOverlayService::class.java.name) {
                    return true
                }
            }
            return false
        }
        
        fun startOverlayService(context: Context, packageName: String) {
            val intent = Intent(context, AppOverlayService::class.java).apply {
                action = "SHOW_OVERLAY"
                putExtra("packageName", packageName)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stopOverlayService(context: Context) {
            val intent = Intent(context, AppOverlayService::class.java).apply {
                action = "HIDE_OVERLAY"
            }
            context.startService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        // CRITICAL: must call startForeground immediately in onCreate on Android 12+
        createNotificationChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("App Restrictions Active")
            .setContentText("Monitoring app access")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "SHOW_OVERLAY" -> {
                val packageName = intent.getStringExtra("packageName")
                if (packageName != null) {
                    showOverlay(packageName)
                }
            }
            "HIDE_OVERLAY" -> {
                hideOverlay()
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
                description = "Manages app restriction overlays"
                setShowBadge(false)
            }
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundNotification() {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("App Restrictions Active")
            .setContentText("Monitoring and restricting app access")
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

    private fun showOverlay(packageName: String) {
        if (overlayView != null) {
            // Already showing an overlay — remove the old one first
            try {
                windowManager?.removeView(overlayView)
            } catch (e: Exception) { /* ignore */ }
            overlayView = null
        }
        
        currentRestrictedPackage = packageName
        startForegroundNotification()
        
        try {
            overlayView = createOverlayView(packageName)
            
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    WindowManager.LayoutParams.TYPE_PHONE
                },
                // FIX: Made overlay FULLY MODAL — intercepts ALL touches so child cannot bypass
                WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                PixelFormat.TRANSLUCENT
            )
            
            windowManager?.addView(overlayView, params)
            Log.d("AppOverlayService", "Overlay shown for: $packageName")
            
        } catch (e: Exception) {
            Log.e("AppOverlayService", "Failed to show overlay: ${e.message}")
            stopSelf()
        }
    }

    private fun createOverlayView(packageName: String): View {
        val inflater = LayoutInflater.from(this)
        val view = inflater.inflate(R.layout.app_overlay_layout, null)
        
        // Get app name for display
        val appName = try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            "This App"
        }
        
        // Custom Messages from SharedPreferences (Synced from Firestore in Flutter)
        val prefs = getSharedPreferences("applocker_local_settings", Context.MODE_PRIVATE)
        val headline = prefs.getString("restrictedHeadline", "App Restricted") ?: "App Restricted"
        val title = prefs.getString("warningTitle", appName) ?: appName
        val warningItems = prefs.getString("warningList", "") ?: ""
        val fallbackMsg = prefs.getString("restrictedMessage", "Access to this application is restricted.") ?: "Access to this application is restricted."
        
        // Set up UI elements
        view.findViewById<TextView>(R.id.overlay_title)?.text = headline.uppercase()
        view.findViewById<TextView>(R.id.overlay_message)?.text = title
        
        val restrictionText = view.findViewById<TextView>(R.id.restriction_message)
        if (warningItems.isNotEmpty()) {
            restrictionText?.text = warningItems
            restrictionText?.visibility = View.VISIBLE
        } else {
            restrictionText?.text = fallbackMsg
            restrictionText?.visibility = View.VISIBLE
        }
        
        val closeButton = view.findViewById<Button>(R.id.close_button)
        // Renamed to "GOT IT" as requested by user suggestion earlier
        closeButton?.text = "GOT IT" 
        closeButton?.setOnClickListener {
            // FIX: Send user home instead of just showing a message
            try {
                val homeIntent = Intent(Intent.ACTION_MAIN)
                homeIntent.addCategory(Intent.CATEGORY_HOME)
                homeIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(homeIntent)
            } catch (e: Exception) {
                Log.e("AppOverlayService", "Failed to go home: ${e.message}")
            }
        }
        
        return view
    }

    private fun hideOverlay() {
        overlayView?.let { view ->
            try {
                windowManager?.removeView(view)
                Log.d("AppOverlayService", "Overlay view removed")
            } catch (e: Exception) {
                Log.e("AppOverlayService", "Failed to remove overlay: ${e.message}")
            }
        }
        overlayView = null
        currentRestrictedPackage = null
        
        // FIX: Don't stop the service — keep it alive so it can re-show instantly
        // The service will be stopped explicitly when no longer needed
        stopForeground(true)
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        hideOverlay()
    }
}
