package com.parentalcontrol.applocker

import android.app.*
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.*
import android.provider.Settings
import android.app.AppOpsManager
import android.util.Log
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.ktx.Firebase
import java.text.SimpleDateFormat
import java.util.*

/**
 * AppLockerBackgroundService
 *
 * Runs as a foreground service to:
 *   1. Poll foreground apps every 300ms for app-blocking
 *   2. Poll Firestore every 10s for lock state changes
 *   3. Show/hide the native system overlay (LockOverlayService) accordingly
 *
 * This service works even when the Flutter app is NOT in the foreground.
 * It's the bridge between Firestore lock commands and the native overlay.
 */
class AppLockerBackgroundService : Service() {

    private val CHANNEL_ID = "AppLockerBackgroundServiceChannel"
    private var blockedApps = mutableListOf<String>()
    private var controlMode = "basic"
    private var tempAccess = mutableMapOf<String, Long>()
    private var appSchedules = mutableMapOf<String, Map<String, Any>>()
    private val handler = Handler(Looper.getMainLooper())
    private val checkInterval = 300L // 300ms for faster app detection

    // Firestore lock polling (backup — real-time listener is the primary mechanism)
    private val lockPollInterval = 60_000L // 60 seconds (backup only)
    // Real-time Firestore listener — receives updates the moment the parent saves
    private var firestoreListener: com.google.firebase.firestore.ListenerRegistration? = null
    private val usagePollInterval = 120_000L // 2 minutes for usage stats sync
    private var deviceId: String = ""
    private var currentPin: String = "1234"
    private var isLocked = false
    private var subscriptionActive = true
    private var appRestrictionOverlayPackage: String? = null
    
    // Local persistence
    private lateinit var sharedPrefs: SharedPreferences
    private lateinit var localPrefs: SharedPreferences
    
    companion object {
        private const val LOCAL_PREFS_NAME = "applocker_local_settings"
        private const val KEY_BLOCKED_APPS = "blocked_apps"
        private const val KEY_CONTROL_MODE = "control_mode"
        private const val KEY_TEMP_ACCESS = "temp_access"
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_PIN = "pin"
        private const val KEY_LAST_SYNC = "last_firestore_sync"
        // Persisted lock state — survives service kills AND device reboots
        private const val KEY_IS_LOCKED = "is_locked"
    }

    // Receiver that re-enforces the lock whenever the screen turns on or
    // the user dismisses the device keyguard (e.g. after a reboot).
    // This is the most reliable way to guarantee the overlay reappears
    // even when Android's own lock screen was shown first on boot.
    private val screenReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_USER_PRESENT,   // user unlocked keyguard
                Intent.ACTION_SCREEN_ON -> {  // screen woke up
                    if (isLocked) {
                        Log.d("AppLockerService", "Screen/user-present event — re-enforcing lock overlay")
                        // Small delay to let the window system settle
                        handler.postDelayed({ if (isLocked) showNativeOverlay() }, 300)
                    }
                }
            }
        }
    }
    private var screenReceiverRegistered = false

    // App blocking runnable
    private val checkRunnable = object : Runnable {
        override fun run() {
            checkForegroundApp()
            handler.postDelayed(this, checkInterval)
        }
    }

    // Firestore lock state polling runnable
    private val lockPollRunnable = object : Runnable {
        override fun run() {
            pollFirestoreLockState()
            handler.postDelayed(this, lockPollInterval)
        }
    }

    // Usage stats sync runnable
    private val usageSyncRunnable = object : Runnable {
        override fun run() {
            syncUsageStats()
            handler.postDelayed(this, usagePollInterval)
        }
    }

    override fun onCreate() {
        super.onCreate()

        // CRITICAL: startForeground MUST be called within 5 seconds on Android 12+
        // Call it FIRST before any other initialization
        createNotificationChannel()
        val notification = createNotification("Parental Control Active")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(9001, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(9001, notification)
        }

        // Safe to do slower initialization AFTER startForeground
        sharedPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        localPrefs = getSharedPreferences(LOCAL_PREFS_NAME, Context.MODE_PRIVATE)
        loadLocalSettings()

        val flutterDeviceId = sharedPrefs.getString("flutter.deviceId", "") ?: ""
        if (flutterDeviceId.isNotEmpty()) {
            deviceId = flutterDeviceId
            localPrefs.edit().putString(KEY_DEVICE_ID, deviceId).apply()
        }

        Log.d("AppLockerService", "onCreate deviceId=$deviceId, blockedApps=${blockedApps.size}")

        try {
            if (FirebaseApp.getApps(this).isEmpty()) {
                FirebaseApp.initializeApp(this)
            }
        } catch (e: Exception) {
            Log.e("AppLockerService", "Firebase init error: ${e.message}")
        }

        // Register receiver for screen-on / user-present so we can
        // re-show the overlay immediately after the keyguard is dismissed.
        // These two actions CANNOT be declared in the manifest — they must
        // be registered dynamically.
        try {
            val filter = android.content.IntentFilter().apply {
                addAction(Intent.ACTION_USER_PRESENT)
                addAction(Intent.ACTION_SCREEN_ON)
            }
            registerReceiver(screenReceiver, filter)
            screenReceiverRegistered = true
            Log.d("AppLockerService", "Screen/user-present receiver registered")
        } catch (e: Exception) {
            Log.e("AppLockerService", "Failed to register screen receiver: ${e.message}")
        }

        // Start loops with a small delay to let Firebase settle
        handler.postDelayed({
            handler.post(checkRunnable)
            if (deviceId.isNotEmpty()) {
                setupFirestoreRealtimeListener()
                handler.post(lockPollRunnable)   // 60 s backup poll
                handler.post(usageSyncRunnable)
            } else {
                val backupDeviceId = localPrefs.getString(KEY_DEVICE_ID, "") ?: ""
                if (backupDeviceId.isNotEmpty()) {
                    deviceId = backupDeviceId
                    Log.d("AppLockerService", "Recovered deviceId from local backup: $deviceId")
                    setupFirestoreRealtimeListener()
                    handler.post(lockPollRunnable)
                    handler.post(usageSyncRunnable)
                }
            }
        }, 1000)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val apps = intent?.getStringArrayListExtra("blockedApps")
            val mode = intent?.getStringExtra("controlMode")
            @Suppress("UNCHECKED_CAST")
            val temps = intent?.getSerializableExtra("tempAccess") as? HashMap<String, Long>
            @Suppress("UNCHECKED_CAST")
            val schedules = intent?.getSerializableExtra("appSchedules") as? HashMap<String, Map<String, Any>>
            val action = intent?.getStringExtra("action") ?: "sync"
            val devId = intent?.getStringExtra("deviceId")
            val pin = intent?.getStringExtra("pin")

            if (apps != null) blockedApps = apps.toMutableList()
            if (mode != null) controlMode = mode
            if (temps != null) tempAccess = temps.toMutableMap()
            if (schedules != null) appSchedules = schedules.toMutableMap()
            
            if (devId != null && devId.isNotEmpty()) {
                val newDevice = devId != deviceId
                deviceId = devId
                localPrefs.edit().putString(KEY_DEVICE_ID, deviceId).apply()
                if (newDevice) {
                    // New device ID — set up the real-time listener for this device
                    setupFirestoreRealtimeListener()
                }
                // Backup poll: reschedule to run soon
                handler.removeCallbacks(lockPollRunnable)
                handler.postDelayed(lockPollRunnable, 2000)
            }
            if (pin != null) {
                currentPin = pin
                localPrefs.edit().putString(KEY_PIN, currentPin).apply()
            }
            
            if (apps != null || mode != null || temps != null) {
                saveLocalSettings()
            }

            when (action) {
                "lock" -> {
                    isLocked = true
                    localPrefs.edit().putBoolean(KEY_IS_LOCKED, true).apply()
                    showNativeOverlay()
                }
                "unlock" -> {
                    isLocked = false
                    localPrefs.edit().putBoolean(KEY_IS_LOCKED, false).apply()
                    handler.removeCallbacks(bootRetryRunnable)
                    hideNativeOverlay()
                }
                // On boot: immediately restore lock state from local persistence
                // This ensures the overlay reappears before the first Firestore poll.
                "boot" -> {
                    val wasLocked = localPrefs.getBoolean(KEY_IS_LOCKED, false)
                    Log.d("AppLockerService", "Boot action: wasLocked=$wasLocked")
                    if (wasLocked) {
                        isLocked = true
                        startBootLockRetryLoop()
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("AppLockerService", "Safety Catch: ${e.message}")
        }
        return START_STICKY
    }

    /**
     * Applies all fields from a Firestore device document to the local service state.
     * Called from both the real-time snapshot listener and the backup poll.
     */
    private fun applyFirestoreDoc(doc: com.google.firebase.firestore.DocumentSnapshot) {
        if (!doc.exists()) {
            Log.d("AppLockerService", "applyFirestoreDoc: doc not found for $deviceId")
            return
        }

        val manualLock = doc.getBoolean("locked") ?: false
        val subActive = doc.getBoolean("subscriptionActive") ?: true
        subscriptionActive = subActive
        currentPin = doc.getString("pin") ?: "1234"

        val blockedAppsFromFirestore = doc.get("blockedApps") as? List<String> ?: mutableListOf()
        val hiddenAppsFromFirestore = doc.get("hiddenApps") as? List<String> ?: mutableListOf()
        val controlModeFromFirestore = doc.getString("controlMode") ?: "basic"

        // Deserialize tempAccess — Firestore stores Timestamps, not Longs
        val tempAccessRaw = doc.get("tempAccess") as? Map<String, Any> ?: mapOf()
        val tempAccessParsed = hashMapOf<String, Long>()
        for ((key, value) in tempAccessRaw) {
            when (value) {
                is com.google.firebase.Timestamp -> tempAccessParsed[key] = value.toDate().time
                is Long   -> tempAccessParsed[key] = value
                is Double -> tempAccessParsed[key] = value.toLong()
                is Number -> tempAccessParsed[key] = value.toLong()
                else -> Log.w("AppLockerService", "Unexpected tempAccess type for $key: ${value?.javaClass?.name}")
            }
        }

        // Deserialize appSchedules (nested maps)
        val appSchedulesRaw = doc.get("appSchedules") as? Map<String, Any> ?: mapOf()
        val appSchedulesParsed = hashMapOf<String, Map<String, Any>>()
        for ((key, value) in appSchedulesRaw) {
            if (value is Map<*, *>) {
                @Suppress("UNCHECKED_CAST")
                appSchedulesParsed[key] = value as Map<String, Any>
            }
        }

        Log.d("AppLockerService", "Firestore update: blockedApps=${blockedAppsFromFirestore.size} hiddenApps=${hiddenAppsFromFirestore.size} mode=$controlModeFromFirestore tempAccess=${tempAccessParsed.size} appSchedules=${appSchedulesParsed.size}")

        // Apply to local state immediately — checkForegroundApp() will pick this up on the next 300ms tick
        blockedApps = blockedAppsFromFirestore.toMutableList()
        controlMode = controlModeFromFirestore
        tempAccess = tempAccessParsed
        appSchedules = appSchedulesParsed

        // Persist custom overlay messages
        val lockHeadline      = doc.getString("lockHeadline")      ?: "LOCKED"
        val lockMessage       = doc.getString("lockMessage")       ?: "Enter PIN Code to unlock"
        val taskTitle         = doc.getString("taskTitle")         ?: "To-Do List"
        val taskListRaw       = doc.get("taskList") as? List<String> ?: listOf()
        val restrictedHeadline = doc.getString("restrictedHeadline") ?: "App Restricted"
        val restrictedMessage  = doc.getString("restrictedMessage")  ?: "This app is restricted by your parent."
        val warningTitle      = doc.getString("warningTitle")      ?: "Restricted Access"
        val warningListRaw    = doc.get("warningList") as? List<String> ?: listOf()
        val smsReceiverNumber = doc.getString("smsReceiverNumber") ?: ""

        localPrefs.edit()
            .putString("lockHeadline",       lockHeadline)
            .putString("lockMessage",        lockMessage)
            .putString("taskTitle",          taskTitle)
            .putString("taskList",           taskListRaw.joinToString("\n"))
            .putString("restrictedHeadline", restrictedHeadline)
            .putString("restrictedMessage",  restrictedMessage)
            .putString("warningTitle",       warningTitle)
            .putString("warningList",        warningListRaw.joinToString("\n"))
            .putString("smsReceiverNumber",  smsReceiverNumber)
            .putLong(KEY_LAST_SYNC, System.currentTimeMillis())
            .apply()

        saveLocalSettings()

        if (subscriptionActive) {
            applyAppHiding(hiddenAppsFromFirestore)
        } else {
            applyAppHiding(listOf())
        }

        val scheduleLocked = isScheduleActive(doc)
        val shouldLock = subscriptionActive && (manualLock || scheduleLocked)

        Log.d("AppLockerService", "shouldLock=$shouldLock (manual=$manualLock schedule=$scheduleLocked currently=$isLocked)")

        if (shouldLock && !isLocked) {
            isLocked = true
            localPrefs.edit().putBoolean(KEY_IS_LOCKED, true).apply()
            showNativeOverlay()
        } else if (!shouldLock && isLocked) {
            isLocked = false
            localPrefs.edit().putBoolean(KEY_IS_LOCKED, false).apply()
            handler.removeCallbacks(bootRetryRunnable)
            hideNativeOverlay()
        }

        LockOverlayService.overlayPin      = currentPin
        LockOverlayService.overlayDeviceId = deviceId
    }

    /**
     * Registers a real-time Firestore snapshot listener so that ANY change the
     * parent makes on the dashboard is reflected on the child device within
     * milliseconds — no more 10-second polling delay.
     *
     * The backup poll (lockPollRunnable, every 60 s) handles reconnection
     * scenarios where the listener might have silently dropped.
     */
    private fun setupFirestoreRealtimeListener() {
        if (deviceId.isEmpty()) return

        // Remove any existing listener before registering a new one
        firestoreListener?.remove()
        firestoreListener = null

        try {
            val db = FirebaseFirestore.getInstance()
            firestoreListener = db.collection("devices").document(deviceId)
                .addSnapshotListener(com.google.firebase.firestore.MetadataChanges.EXCLUDE) { snap, err ->
                    if (err != null) {
                        Log.e("AppLockerService", "Firestore snapshot error: ${err.message}")
                        return@addSnapshotListener
                    }
                    if (snap == null) return@addSnapshotListener
                    Log.d("AppLockerService", "Firestore real-time update received")
                    applyFirestoreDoc(snap)
                }
            Log.d("AppLockerService", "Firestore real-time listener registered for $deviceId")
        } catch (e: Exception) {
            Log.e("AppLockerService", "setupFirestoreRealtimeListener error: ${e.message}")
        }
    }

    /**
     * Backup poll — runs every 60 s to catch any listener drop due to network
     * changes.  Uses the same applyFirestoreDoc() logic as the real-time path.
     */
    private fun pollFirestoreLockState() {
        if (deviceId.isEmpty()) return
        try {
            FirebaseFirestore.getInstance()
                .collection("devices").document(deviceId).get()
                .addOnSuccessListener { doc -> if (doc != null) applyFirestoreDoc(doc) }
                .addOnFailureListener { e -> Log.e("AppLockerService", "Backup poll failed: ${e.message}") }
        } catch (e: Exception) {
            Log.e("AppLockerService", "pollFirestoreLockState error: ${e.message}")
        }
    }

    /**
     * Checks if any enabled lock schedule is currently active.
     *
     * Flutter saves times in "HH:mm" 24-hour format (e.g. "22:00", "06:30").
     * We parse by splitting on ":" directly — no SimpleDateFormat needed.
     */
    private fun isScheduleActive(doc: com.google.firebase.firestore.DocumentSnapshot): Boolean {
        try {
            val schedules = doc.get("lockSchedules") as? List<Map<String, Any>> ?: return false
            if (schedules.isEmpty()) return false

            val nowCal = java.util.Calendar.getInstance()
            val nowMins = nowCal.get(java.util.Calendar.HOUR_OF_DAY) * 60 +
                          nowCal.get(java.util.Calendar.MINUTE)

            // Parse "HH:mm" string to minutes-since-midnight
            fun toMins(timeStr: String): Int? {
                return try {
                    val parts = timeStr.trim().split(":")
                    if (parts.size < 2) return null
                    val h = parts[0].trim().toIntOrNull() ?: return null
                    val m = parts[1].trim().take(2).toIntOrNull() ?: return null
                    h * 60 + m
                } catch (e: Exception) {
                    Log.e("AppLockerService", "toMins parse error for '$timeStr': ${e.message}")
                    null
                }
            }

            for (schedule in schedules) {
                val enabled = schedule["enabled"] as? Boolean ?: true
                if (!enabled) continue

                val startStr = schedule["start"] as? String ?: continue
                val endStr   = schedule["end"]   as? String ?: continue

                try {
                    val startMins = toMins(startStr) ?: continue
                    val endMins   = toMins(endStr)   ?: continue

                    val active = if (endMins <= startMins) {
                        // Overnight schedule e.g. 22:00 → 06:00
                        nowMins >= startMins || nowMins < endMins
                    } else {
                        nowMins >= startMins && nowMins < endMins
                    }

                    Log.d("AppLockerService", "LockSchedule $startStr-$endStr: nowMins=$nowMins startMins=$startMins endMins=$endMins active=$active")
                    if (active) return true
                } catch (e: Exception) {
                    Log.e("AppLockerService", "Error evaluating lock schedule item: ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.e("AppLockerService", "isScheduleActive error: ${e.message}")
        }
        return false
    }

    /**
     * On boot, the window system may not be ready immediately, so this loop
     * retries every 5 seconds for up to 3 minutes until the overlay is shown.
     */
    private var bootRetryCount = 0
    private val bootRetryRunnable = object : Runnable {
        override fun run() {
            if (!isLocked) {
                Log.d("AppLockerService", "Boot retry: device unlocked, stopping")
                bootRetryCount = 0
                return
            }
            if (LockOverlayService.isShowing) {
                Log.d("AppLockerService", "Boot retry: overlay confirmed showing, stopping")
                bootRetryCount = 0
                return
            }
            bootRetryCount++
            // 36 attempts × 5 s = 3 minutes max
            if (bootRetryCount > 36) {
                Log.w("AppLockerService", "Boot retry: gave up after 3 minutes")
                bootRetryCount = 0
                return
            }
            Log.d("AppLockerService", "Boot retry #$bootRetryCount — attempting showNativeOverlay")
            showNativeOverlay()
            handler.postDelayed(this, 5_000L)
        }
    }

    private fun startBootLockRetryLoop() {
        handler.removeCallbacks(bootRetryRunnable)
        bootRetryCount = 0
        // First attempt almost immediately, then every 5 s via the runnable
        handler.postDelayed(bootRetryRunnable, 500L)
    }

    /**
     * Shows the native system overlay via LockOverlayService
     */
    private fun showNativeOverlay() {
        Log.d("AppLockerService", "🔒 Showing native system overlay")
        
        if (!android.provider.Settings.canDrawOverlays(this)) {
            Log.e("AppLockerService", "Cannot show overlay: SYSTEM_ALERT_WINDOW not granted")
            // Fallback: bring Flutter app to foreground
            bringAppToForeground(null)
            return
        }

        val intent = Intent(this, LockOverlayService::class.java).apply {
            putExtra("action", "show")
            putExtra("pin", currentPin)
            putExtra("deviceId", deviceId)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    /**
     * Hides the native system overlay
     */
    private fun hideNativeOverlay() {
        Log.d("AppLockerService", "🔓 Hiding native system overlay")
        val intent = Intent(this, LockOverlayService::class.java).apply {
            putExtra("action", "hide")
        }
        try {
            startService(intent)
        } catch (e: Exception) {
            // Service might not be running, that's fine
            Log.d("AppLockerService", "hideNativeOverlay: service not running")
        }
    }

    private var lastKnownForegroundPackage: String? = null

    private fun checkForegroundApp() {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
        if (usm == null) return

        val time = System.currentTimeMillis()
        
        // 1. Check recent events (most accurate for transitions)
        val events = usm.queryEvents(time - 1000 * 60, time)
        val event = UsageEvents.Event()
        var detectedPackage: String? = null

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                detectedPackage = event.packageName
            }
        }

        // 2. If no recent transition events, fallback to queryUsageStats to find the currently active app
        if (detectedPackage == null) {
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 1000 * 60, time)
            if (stats != null && stats.isNotEmpty()) {
                var lastUsedApp: android.app.usage.UsageStats? = null
                for (usageStats in stats) {
                    if (lastUsedApp == null || usageStats.lastTimeUsed > lastUsedApp.lastTimeUsed) {
                        lastUsedApp = usageStats
                    }
                }
                detectedPackage = lastUsedApp?.packageName
            }
        }

        // 3. Update state
        if (detectedPackage != null) {
            lastKnownForegroundPackage = detectedPackage
        } else {
            // If still null, we use the last known package as a fallback
            detectedPackage = lastKnownForegroundPackage
        }

        if (detectedPackage != null) {
            // Ignore our own apps (Dashboard/Child) to avoid circular locking
            if (detectedPackage == packageName || detectedPackage == "com.parentalcontrol.applocker") {
                hideAppRestrictionOverlayIfNeeded()
                return
            }

            if (!subscriptionActive) {
                hideAppRestrictionOverlayIfNeeded()
                return
            }

            // Block if explicitly blocked OR currently inside a scheduled blocking window
            val explicitlyBlocked = blockedApps.contains(detectedPackage)
            val scheduleBlocking  = isScheduledToBlockNow(detectedPackage)

            if (explicitlyBlocked || scheduleBlocking) {
                // Check for Timed Access — grants temporary bypass regardless of block source
                val expiry = tempAccess[detectedPackage]
                if (expiry != null && expiry > time) {
                    hideAppRestrictionOverlayIfNeeded()
                    return
                }

                // If device is already fully locked, don't show per-app restriction (it would conflict)
                if (isLocked) {
                    hideAppRestrictionOverlayIfNeeded()
                    return
                }

                showAppRestrictionOverlay(detectedPackage)
            } else {
                hideAppRestrictionOverlayIfNeeded()
            }
        }
    }

    /**
     * Returns true when [packageName] is currently inside its scheduled BLOCKING window.
     *
     * Flutter dashboard saves schedule times in "HH:mm" 24-hour format via
     * `_fmtTimeStore` (e.g. "09:00", "21:30").  The window defined by
     * {start, end} is the period during which the app is BLOCKED ("Block From …
     * Block Until …"), not an allowed window.
     *
     * `alwaysBlocked = true` means block 24/7 regardless of the time window.
     */
    private fun isScheduledToBlockNow(packageName: String): Boolean {
        val schedule = appSchedules[packageName] ?: return false
        val alwaysBlocked = schedule["alwaysBlocked"] as? Boolean ?: false
        if (alwaysBlocked) return true

        val startStr = schedule["start"] as? String ?: return false
        val endStr   = schedule["end"]   as? String ?: return false

        // Parse "HH:mm" to minutes-since-midnight
        fun toMins(timeStr: String): Int? {
            return try {
                val parts = timeStr.trim().split(":")
                if (parts.size < 2) return null
                val h = parts[0].trim().toIntOrNull() ?: return null
                val m = parts[1].trim().take(2).toIntOrNull() ?: return null
                h * 60 + m
            } catch (e: Exception) {
                Log.e("AppLockerService", "isScheduledToBlockNow toMins error for '$timeStr': ${e.message}")
                null
            }
        }

        val nowCal  = java.util.Calendar.getInstance()
        val nowMins = nowCal.get(java.util.Calendar.HOUR_OF_DAY) * 60 +
                      nowCal.get(java.util.Calendar.MINUTE)

        val startMins = toMins(startStr) ?: return false
        val endMins   = toMins(endStr)   ?: return false

        val blocking = if (endMins <= startMins) {
            // Overnight window e.g. 21:00 → 07:00
            nowMins >= startMins || nowMins < endMins
        } else {
            nowMins >= startMins && nowMins < endMins
        }

        Log.d("AppLockerService", "AppSchedule $packageName $startStr-$endStr: nowMins=$nowMins start=$startMins end=$endMins blocking=$blocking")
        return blocking
    }

    private fun showAppRestrictionOverlay(packageName: String) {
        if (appRestrictionOverlayPackage == packageName) {
            return
        }

        if (!Settings.canDrawOverlays(this)) {
            Log.w("AppLockerService", "Overlay permission missing. Falling back to AppLocker foreground UI.")
            bringAppToForeground(packageName)
            return
        }

        try {
            AppOverlayService.startOverlayService(this, packageName)
            appRestrictionOverlayPackage = packageName
            Log.d("AppLockerService", "Showing native app restriction overlay for: $packageName")
        } catch (e: Exception) {
            Log.e("AppLockerService", "Failed to show native app overlay: ${e.message}")
            bringAppToForeground(packageName)
        }
    }

    private fun hideAppRestrictionOverlayIfNeeded() {
        if (appRestrictionOverlayPackage == null) return
        try {
            AppOverlayService.stopOverlayService(this)
            Log.d("AppLockerService", "Hiding native app restriction overlay")
        } catch (e: Exception) {
            Log.e("AppLockerService", "Failed to hide native app overlay: ${e.message}")
        } finally {
            appRestrictionOverlayPackage = null
        }
    }
    
    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val packageManager = packageManager
            val applicationInfo = packageManager.getApplicationInfo("android", PackageManager.GET_META_DATA)
            val appOpsManager = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            if (appOpsManager == null) return false
            
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOpsManager.unsafeCheckOpNoThrow(
                    "android:get_usage_stats",
                    android.os.Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOpsManager.checkOpNoThrow(
                    "android:get_usage_stats",
                    android.os.Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.e("AppLockerService", "Error checking usage permission: ${e.message}")
            false
        }
    }
    
    private fun requestUsageStatsPermission() {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            Log.d("AppLockerService", "Opened usage access settings for user")
        } catch (e: Exception) {
            Log.e("AppLockerService", "Failed to open usage access settings: ${e.message}")
        }
    }

    // Track previously hidden apps so we can unhide removed ones
    private var previouslyHiddenApps = mutableSetOf<String>()
    
    private fun applyAppHiding(hiddenApps: List<String>) {
        try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as? android.app.admin.DevicePolicyManager
            val componentName = android.content.ComponentName(this, AppLockerAdminReceiver::class.java)
            
            // FIX: Check if OUR app is the device owner, not the target app
            val isOwner = dpm != null && (dpm.isDeviceOwnerApp(this.packageName) || dpm.isProfileOwnerApp(this.packageName))
            
            // First: Unhide apps that were previously hidden but are no longer in the list
            val appsToUnhide = previouslyHiddenApps - hiddenApps.toSet()
            for (pkg in appsToUnhide) {
                try {
                    if (isOwner) {
                        dpm!!.setApplicationHidden(componentName, pkg, false)
                        Log.d("AppLockerService", "Unhidden app via Device Admin: $pkg")
                    }
                } catch (e: Exception) {
                    Log.e("AppLockerService", "Failed to unhide $pkg: ${e.message}")
                }
            }
            
            if (isOwner) {
                // Use Device Admin API (most reliable)
                hiddenApps.forEach { pkg ->
                    try {
                        // Don't hide our own app or system launcher
                        if (pkg == this.packageName) return@forEach
                        val success = dpm!!.setApplicationHidden(componentName, pkg, true)
                        Log.d("AppLockerService", "Hidden app via Device Admin: $pkg = $success")
                    } catch (e: Exception) {
                        Log.e("AppLockerService", "Failed to hide $pkg via Device Admin: ${e.message}")
                    }
                }
            } else {
                Log.w("AppLockerService", "App is NOT Device Owner — cannot hide apps. Run: adb shell dpm set-device-owner com.parentalcontrol.applocker/.AppLockerAdminReceiver")
                // Add blocked apps to blockedApps list as fallback (overlay-based blocking)
                hiddenApps.forEach { pkg ->
                    if (!blockedApps.contains(pkg)) {
                        blockedApps.add(pkg)
                        Log.d("AppLockerService", "Fallback: Added $pkg to blockedApps for overlay-based blocking")
                    }
                }
            }
            
            // Update tracking set
            previouslyHiddenApps = hiddenApps.toMutableSet()
        } catch (e: Exception) {
            Log.e("AppLockerService", "applyAppHiding error: ${e.message}")
        }
    }

    private fun bringAppToForeground(pkg: String?) {
        val launchIntent = applicationContext.packageManager.getLaunchIntentForPackage(applicationContext.packageName)
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or 
                         Intent.FLAG_ACTIVITY_SINGLE_TOP or 
                         Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            if (pkg != null) {
                launchIntent.putExtra("blockedPackage", pkg)
                Log.d("AppLockerService", "Setting blockedPackage extra: $pkg")
            }
            startActivity(launchIntent)
            Log.d("AppLockerService", "Brought AppLocker to foreground for blocked app: $pkg")
        } else {
            Log.e("AppLockerService", "Could not get launch intent for AppLocker")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "AppLocker Background Guard",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(content: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AppLocker Guard")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_secure) // Generic lock icon
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun loadLocalSettings() {
        try {
            deviceId = localPrefs.getString(KEY_DEVICE_ID, "") ?: ""
            currentPin = localPrefs.getString(KEY_PIN, "1234") ?: "1234"
            controlMode = localPrefs.getString(KEY_CONTROL_MODE, "basic") ?: "basic"
            // Restore persisted lock state — critical for boot scenario
            isLocked = localPrefs.getBoolean(KEY_IS_LOCKED, false)
            
            val blockedAppsJson = localPrefs.getString(KEY_BLOCKED_APPS, null)
            if (blockedAppsJson != null) {
                val appsList = blockedAppsJson.split(",").filter { it.isNotEmpty() }
                blockedApps = appsList.toMutableList()
            }
            
            val tempAccessJson = localPrefs.getString(KEY_TEMP_ACCESS, null)
            if (tempAccessJson != null) {
                try {
                    // Parse simple format: "pkg1:timestamp1,pkg2:timestamp2"
                    val pairs = tempAccessJson.split(",")
                    tempAccess.clear()
                    for (pair in pairs) {
                        val parts = pair.split(":")
                        if (parts.size == 2) {
                            tempAccess[parts[0]] = parts[1].toLongOrNull() ?: 0L
                        }
                    }
                } catch (e: Exception) {
                    Log.e("AppLockerService", "Failed to parse temp access: ${e.message}")
                }
            }
            
            Log.d("AppLockerService", "Loaded local settings: deviceId=$deviceId, blockedApps=${blockedApps.size}, isLocked=$isLocked")
        } catch (e: Exception) {
            Log.e("AppLockerService", "Failed to load local settings: ${e.message}")
        }
    }
    
    private fun saveLocalSettings() {
        try {
            val editor = localPrefs.edit()
            editor.putString(KEY_DEVICE_ID, deviceId)
            editor.putString(KEY_PIN, currentPin)
            editor.putString(KEY_CONTROL_MODE, controlMode)
            editor.putString(KEY_BLOCKED_APPS, blockedApps.joinToString(","))
            
            // Save temp access as simple string
            val tempAccessString = tempAccess.map { "${it.key}:${it.value}" }.joinToString(",")
            editor.putString(KEY_TEMP_ACCESS, tempAccessString)
            editor.apply()
            
            Log.d("AppLockerService", "Saved local settings: blockedApps=${blockedApps.size}")
        } catch (e: Exception) {
            Log.e("AppLockerService", "Failed to save local settings: ${e.message}")
        }
    }
    
    /**
     * Syncs today's app usage stats to Firestore
     */
    private fun syncUsageStats() {
        if (deviceId.isEmpty()) return
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return
        
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()

        val stats = usm.queryAndAggregateUsageStats(startTime, endTime)
        val db = FirebaseFirestore.getInstance()

        val pm = packageManager
        stats.forEach { (pkg, usage) ->
            try {
                val minutes = usage.totalTimeInForeground / 1000 / 60
                if (minutes <= 0) return@forEach // Skip apps with zero usage
                
                var appName = pkg
                try {
                    val appInfo = pm.getApplicationInfo(pkg, 0)
                    appName = pm.getApplicationLabel(appInfo).toString()
                } catch (_: Exception) {}

                val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
                val docId = "${todayStr}_$pkg"

                val activity = hashMapOf(
                    "type" to "app_usage",
                    "packageName" to pkg,
                    "appName" to appName,
                    "duration" to minutes,
                    "timestamp" to FieldValue.serverTimestamp(),
                    "deviceId" to deviceId
                )

                db.collection("devices")
                    .document(deviceId)
                    .collection("activity")
                    .document(docId)
                    .set(activity)
                    .addOnFailureListener { e ->
                        Log.e("AppLockerService", "Failed to sync usage for $pkg: ${e.message}")
                    }
            } catch (e: Exception) {
                Log.e("AppLockerService", "Error processing usage for $pkg: ${e.message}")
            }
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(checkRunnable)
        handler.removeCallbacks(lockPollRunnable)
        handler.removeCallbacks(usageSyncRunnable)
        handler.removeCallbacks(bootRetryRunnable)
        firestoreListener?.remove()
        firestoreListener = null
        hideAppRestrictionOverlayIfNeeded()
        saveLocalSettings()
        if (screenReceiverRegistered) {
            try {
                unregisterReceiver(screenReceiver)
                screenReceiverRegistered = false
            } catch (e: Exception) {
                Log.e("AppLockerService", "Failed to unregister screen receiver: ${e.message}")
            }
        }
        super.onDestroy()
    }
}
