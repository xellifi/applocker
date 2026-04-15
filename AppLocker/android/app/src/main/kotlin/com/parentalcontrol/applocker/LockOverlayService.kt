package com.parentalcontrol.applocker

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.text.InputType
import android.util.Log
import android.util.TypedValue
import android.view.*
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.*
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat

/**
 * LockOverlayService
 *
 * Draws a full-screen SYSTEM_ALERT_WINDOW overlay on top of ALL apps.
 * This is the KEY piece that makes the lock work even when:
 *   - The child is on the home screen
 *   - The child is in another app
 *   - The device is idle
 *   - The Flutter app is NOT in the foreground
 *
 * Features:
 *   - Amber/yellow full-screen lock UI matching the Flutter design
 *   - PIN entry with validation
 *   - Blocks back button, home button (via TYPE_APPLICATION_OVERLAY)
 *   - Communicates unlock back to Firestore
 *
 * Triggered by:
 *   - AppLockerBackgroundService (Firestore poll detects lock=true)
 *   - FCM push notification with command 'show_overlay'
 *   - Flutter MethodChannel call 'showNativeOverlay'
 */
class LockOverlayService : Service() {

    companion object {
        private const val TAG = "LockOverlayService"
        private const val CHANNEL_ID = "LockOverlayChannel"
        private const val NOTIFICATION_ID = 9002
        
        // Static state so other services/activities can check
        @Volatile
        var isShowing = false
            private set

        var overlayPin = "1234"
        var overlayDeviceId = ""
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null

    override fun onCreate() {
        super.onCreate()
        // CRITICAL: startForeground MUST come first — before Firebase or any slow init
        createNotificationChannel()
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // Firebase init AFTER startForeground (safe)
        if (com.google.firebase.FirebaseApp.getApps(this).isEmpty()) {
            com.google.firebase.FirebaseApp.initializeApp(this)
        }
        Log.d(TAG, "LockOverlayService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val action = intent?.getStringExtra("action") ?: "show"
            val pin = intent?.getStringExtra("pin")
            val devId = intent?.getStringExtra("deviceId")

            if (pin != null) overlayPin = pin
            if (devId != null) overlayDeviceId = devId

            when (action) {
                "show" -> showOverlay()
                "hide" -> hideOverlay()
                "updatePin" -> { /* pin already updated */ }
            }
        } catch (e: Exception) {
            Log.e(TAG, "onStartCommand safety catch: ${e.message}")
        }
        return START_STICKY
    }

    private fun showOverlay() {
        if (isShowing) {
            Log.d(TAG, "Overlay already showing, skipping")
            return
        }

        if (!android.provider.Settings.canDrawOverlays(this)) {
            Log.e(TAG, "SYSTEM_ALERT_WINDOW permission not granted!")
            return
        }

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            // These flags make it:
            // - Cover the entire screen including status bar
            // - Intercept all touch events
            // - Stay on top of lock screen
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or  // Start non-focusable, switch when PIN needed
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            PixelFormat.OPAQUE
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = 0
        params.y = 0

        overlayView = createOverlayView()

        try {
            windowManager?.addView(overlayView, params)
            isShowing = true
            Log.d(TAG, "✅ System overlay SHOWN on top of everything")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add overlay view: ${e.message}")
        }
    }

    private fun hideOverlay() {
        try {
            if (overlayView != null && windowManager != null) {
                windowManager?.removeView(overlayView)
                overlayView = null
                isShowing = false
                Log.d(TAG, "✅ System overlay HIDDEN")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to remove overlay: ${e.message}")
        }
        stopSelf()
    }

    private fun createOverlayView(): View {
        val context = this

        // Root layout - full screen amber background
        val root = FrameLayout(context).apply {
            setBackgroundColor(Color.parseColor("#FBBC05")) // Amber 600
            isFocusable = true
            isClickable = true
        }

        // Center card container
        val scrollView = ScrollView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            isFillViewport = true
        }

        val centerWrapper = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
            setPadding(dpToPx(32), dpToPx(48), dpToPx(32), dpToPx(48))
        }

        // Lock icon - circle with lock
        val iconSize = dpToPx(120)
        val iconContainer = FrameLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(iconSize, iconSize).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        }

        // Circle border
        val circleView = View(context).apply {
            layoutParams = FrameLayout.LayoutParams(iconSize, iconSize)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setStroke(dpToPx(4), Color.BLACK)
                setColor(Color.TRANSPARENT)
            }
        }
        iconContainer.addView(circleView)

        // Lock text (using emoji as icon since we don't have vector drawables easily)
        val lockIcon = TextView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER }
            text = "🔒"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 48f)
        }
        iconContainer.addView(lockIcon)

        centerWrapper.addView(iconContainer)

        // Spacer
        centerWrapper.addView(createSpacer(32))

        val prefs = getSharedPreferences("applocker_local_settings", Context.MODE_PRIVATE)
        val headlineText = prefs.getString("lockHeadline", "LOCKED") ?: "LOCKED"
        val messageText = prefs.getString("lockMessage", "Enter PIN Code to unlock") ?: "Enter PIN Code to unlock"

        // Headline title (Customizable)
        val title = TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER_HORIZONTAL }
            text = headlineText.uppercase()
            setTextColor(Color.BLACK)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 36f)
            setTypeface(null, Typeface.BOLD)
            letterSpacing = 0.05f
            gravity = Gravity.CENTER
        }
        centerWrapper.addView(title)

        centerWrapper.addView(createSpacer(32))

        // Message/Subtitle text (Customizable)
        val subtitle = TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER_HORIZONTAL }
            text = messageText
            setTextColor(Color.BLACK)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(dpToPx(16), 0, dpToPx(16), 0)
        }
        centerWrapper.addView(subtitle)

        centerWrapper.addView(createSpacer(16))

        // PIN Input container
        val pinContainer = LinearLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dpToPx(60)
            )
            background = GradientDrawable().apply {
                cornerRadius = dpToPx(8).toFloat()
                setStroke(dpToPx(1), Color.BLACK)
                setColor(Color.TRANSPARENT)
            }
            gravity = Gravity.CENTER
        }

        val pinInput = EditText(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
            setTextColor(Color.BLACK)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            setTypeface(null, Typeface.BOLD)
            letterSpacing = 0.5f
            gravity = Gravity.CENTER
            inputType = InputType.TYPE_CLASS_NUMBER
            hint = "* * * * * *"
            setHintTextColor(Color.parseColor("#61000000"))
            background = null
            isSingleLine = true
            imeOptions = EditorInfo.IME_ACTION_DONE
            maxEms = 6
        }
        pinContainer.addView(pinInput)
        centerWrapper.addView(pinContainer)

        // Error text (hidden initially)
        val errorText = TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dpToPx(8)
            }
            text = "INCORRECT PIN"
            setTextColor(Color.RED)
            setTypeface(null, Typeface.BOLD)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            visibility = View.INVISIBLE
        }
        centerWrapper.addView(errorText)

        // GAP between PIN and Task Box: 10dp
        centerWrapper.addView(createSpacer(10))

        // Dynamic Task List
        val taskTitle = prefs.getString("taskTitle", "") ?: ""
        val taskItems = prefs.getString("taskList", "") ?: ""
        
        if (taskTitle.isNotEmpty() || taskItems.isNotEmpty()) {
            val taskContainer = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                )
                background = GradientDrawable().apply {
                    cornerRadius = dpToPx(12).toFloat()
                    setColor(Color.TRANSPARENT)
                    setStroke(dpToPx(1), Color.BLACK)
                }
                setPadding(dpToPx(20), dpToPx(20), dpToPx(20), dpToPx(20))
            }

            if (taskTitle.isNotEmpty()) {
                taskContainer.addView(TextView(context).apply {
                    text = taskTitle.uppercase()
                    setTextColor(Color.parseColor("#E65100")) // Deep Orange
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    setTypeface(null, Typeface.BOLD)
                    letterSpacing = 0.1f
                })
                taskContainer.addView(createSpacer(12))
            }

            if (taskItems.isNotEmpty()) {
                // Clean any starting bullets in taskItems
                val cleanItems = taskItems.replace(Regex("^[•\\-*]\\s*"), "").trim()
                taskContainer.addView(TextView(context).apply {
                    text = cleanItems
                    setTextColor(Color.BLACK)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    setTypeface(null, Typeface.BOLD)
                    setLineSpacing(0f, 1.2f)
                })
            }
            centerWrapper.addView(taskContainer)
        }

        centerWrapper.addView(createSpacer(24))

        // "Device is locked by parent" info text (Footer)
        val infoText = TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER_HORIZONTAL }
            text = "This device is temporarily locked.\nComplete the tasks or enter PIN to unlock."
            setTextColor(Color.parseColor("#99000000"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            setLineSpacing(dpToPx(4).toFloat(), 1f)
        }
        centerWrapper.addView(infoText)

        // Handle PIN validation
        pinInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                validatePin(pinInput, errorText)
                true
            } else false
        }

        // Auto-validate when PIN length matches
        pinInput.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) {
                val text = s?.toString() ?: ""
                if (text.length >= overlayPin.length) {
                    validatePin(pinInput, errorText)
                }
            }
        })

        // When PIN input is tapped, make the window focusable so keyboard works
        pinInput.setOnClickListener {
            makeFocusable()
        }
        pinInput.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) makeFocusable()
        }

        scrollView.addView(centerWrapper)
        root.addView(scrollView)

        return root
    }

    private fun makeFocusable() {
        try {
            val params = overlayView?.layoutParams as? WindowManager.LayoutParams ?: return
            // Remove NOT_FOCUSABLE flag so keyboard can appear
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            windowManager?.updateViewLayout(overlayView, params)
            Log.d(TAG, "Overlay made focusable for keyboard input")
        } catch (e: Exception) {
            Log.e(TAG, "makeFocusable error: ${e.message}")
        }
    }

    private fun validatePin(pinInput: EditText, errorText: TextView) {
        val entered = pinInput.text.toString().trim()
        Log.d(TAG, "PIN attempt: $entered (correct: $overlayPin)")

        if (entered == overlayPin) {
            Log.d(TAG, "✅ PIN correct! Unlocking...")
            // Update Firestore to unlock
            unlockViaFirestore()
            // Notify Flutter side
            notifyFlutterUnlock()
            // Hide the overlay
            hideOverlay()
        } else {
            Log.d(TAG, "❌ PIN incorrect")
            errorText.visibility = View.VISIBLE
            pinInput.text.clear()
            // Hide error after 2 seconds
            pinInput.postDelayed({
                errorText.visibility = View.GONE
            }, 2000)
        }
    }

    private fun unlockViaFirestore() {
        if (overlayDeviceId.isEmpty()) {
            Log.w(TAG, "No deviceId, can't update Firestore")
            return
        }
        // Use a background thread to update Firestore
        Thread {
            try {
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("devices")
                    .document(overlayDeviceId)
                    .update(mapOf(
                        "locked" to false,
                        "pendingCommand" to com.google.firebase.firestore.FieldValue.delete()
                    ))
                Log.d(TAG, "Firestore updated: locked=false for $overlayDeviceId")
            } catch (e: Exception) {
                Log.e(TAG, "Firestore unlock update failed: ${e.message}")
            }
        }.start()
    }

    private fun notifyFlutterUnlock() {
        // Send broadcast that Flutter can pickup, or use shared prefs
        try {
            val prefs = getSharedPreferences("lock_state", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("locked", false).apply()
            
            // Also send a broadcast for the background service
            val intent = Intent("com.parentalcontrol.UNLOCK_EVENT")
            sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "notifyFlutterUnlock error: ${e.message}")
        }
    }

    private fun createSpacer(dpHeight: Int): View {
        return View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dpToPx(dpHeight)
            )
        }
    }

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Lock Overlay",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when device is locked by parent"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Device Locked")
            .setContentText("This device is locked.")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        hideOverlay()
        super.onDestroy()
        Log.d(TAG, "LockOverlayService destroyed")
    }
}
