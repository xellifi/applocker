package com.parentalcontrol.applocker

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.Log
import android.util.TypedValue
import android.view.*
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.*
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat

/**
 * LockOverlayService — native SYSTEM_ALERT_WINDOW overlay.
 * Features:
 *   - Full-screen yellow lock UI
 *   - MESSAGE button → in-overlay chat panel (Firestore real-time)
 *   - CALL button → in-overlay dial pad → launches system dialer
 *   - Hidden 10-tap emergency PIN unlock on lock icon
 */
class LockOverlayService : Service() {

    companion object {
        private const val TAG = "LockOverlayService"
        private const val CHANNEL_ID = "LockOverlayChannel"
        private const val NOTIFICATION_ID = 9002

        @Volatile var isShowing = false
            private set

        var overlayPin   = "1234"
        var overlayDeviceId = ""
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null

    // Emergency tap counter
    private var emergencyTapCount = 0
    private val tapResetHandler = Handler(Looper.getMainLooper())
    private val tapResetRunnable = Runnable { emergencyTapCount = 0 }

    // Firestore chat listener handle
    private var chatListener: com.google.firebase.firestore.ListenerRegistration? = null
    private var chatMessagesLayout: LinearLayout? = null
    private var chatScrollView: ScrollView? = null
    private var panelKeyboardListener: ViewTreeObserver.OnGlobalLayoutListener? = null
    private var panelKeyboardRoot: View? = null


    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        if (com.google.firebase.FirebaseApp.getApps(this).isEmpty()) {
            com.google.firebase.FirebaseApp.initializeApp(this)
        }
        Log.d(TAG, "LockOverlayService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val prefs = getSharedPreferences("applocker_local_settings", Context.MODE_PRIVATE)
            val action = intent?.getStringExtra("action") ?: "show"
            val pin   = intent?.getStringExtra("pin")
            val devId = intent?.getStringExtra("deviceId")
            // Update and persist if provided
            if (pin != null) {
                overlayPin = pin
                prefs.edit().putString("pin", pin).apply()
            }
            if (devId != null) {
                overlayDeviceId = devId
                prefs.edit().putString("deviceId", devId).apply()
            }
            // Fallback: load from SharedPreferences if companion vars are still empty
            // (happens when process is killed and START_STICKY restarts service with null intent)
            if (overlayPin.isEmpty() || overlayPin == "1234") {
                val savedPin = prefs.getString("pin", "") ?: ""
                if (savedPin.isNotEmpty()) overlayPin = savedPin
            }
            if (overlayDeviceId.isEmpty()) {
                overlayDeviceId = prefs.getString("deviceId", "") ?: ""
            }
            when (action) {
                "show" -> showOverlay()
                "hide" -> hideOverlay()
            }
        } catch (e: Exception) {
            Log.e(TAG, "onStartCommand: ${e.message}")
        }
        return START_STICKY
    }

    // ── Show / Hide ────────────────────────────────────────────────────────────

    private fun showOverlay() {
        if (isShowing) return
        if (!android.provider.Settings.canDrawOverlays(this)) {
            Log.e(TAG, "SYSTEM_ALERT_WINDOW not granted"); return
        }
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            PixelFormat.OPAQUE
        )
        params.gravity = Gravity.TOP or Gravity.START
        overlayView = createOverlayView()
        try {
            windowManager?.addView(overlayView, params)
            isShowing = true
            Log.d(TAG, "✅ Overlay shown")
        } catch (e: Exception) {
            Log.e(TAG, "addView failed: ${e.message}")
        }
    }

    private fun hideOverlay() {
        chatListener?.remove(); chatListener = null
        clearPanelKeyboardLift()
        try {
            if (overlayView != null && windowManager != null) {
                windowManager?.removeView(overlayView)
                overlayView = null
                isShowing = false
            }
        } catch (e: Exception) {
            Log.e(TAG, "removeView failed: ${e.message}")
        }
        stopSelf()
    }

    // ── Root overlay view ──────────────────────────────────────────────────────

    private fun createOverlayView(): View {
        val ctx = this
        val prefs = getSharedPreferences("applocker_local_settings", Context.MODE_PRIVATE)

        // ── Root: amber background, full screen
        val root = FrameLayout(ctx).apply {
            setBackgroundColor(Color.parseColor("#FBBC05"))
            isFocusable  = true
            isClickable  = true
        }

        // ── Scrollable main content
        val scroll = ScrollView(ctx).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            isFillViewport = true
        }

        val content = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
            setPadding(dp(28), dp(44), dp(28), dp(36))
        }

        // ── Profile photo (set by admin in dashboard settings)
        val profileImageUrl = prefs.getString("profileImageUrl", "") ?: ""
        if (profileImageUrl.isNotEmpty()) {
            val avatarSize = dp(88)
            val avatarView = android.widget.ImageView(ctx).apply {
                layoutParams = LinearLayout.LayoutParams(avatarSize, avatarSize).apply {
                    gravity = Gravity.CENTER_HORIZONTAL
                }
                scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.parseColor("#22000000"))
                    setStroke(dp(3), Color.BLACK)
                }
            }
            content.addView(avatarView)
            content.addView(spacer(14))
            // Load image on background thread, render circular bitmap
            Thread {
                try {
                    val url = java.net.URL(profileImageUrl)
                    val conn = url.openConnection() as java.net.HttpURLConnection
                    conn.connectTimeout = 6000
                    conn.readTimeout = 10000
                    conn.connect()
                    val rawBmp = android.graphics.BitmapFactory.decodeStream(conn.inputStream)
                    conn.disconnect()
                    if (rawBmp != null) {
                        val dim = minOf(rawBmp.width, rawBmp.height)
                        val xOff = (rawBmp.width - dim) / 2
                        val yOff = (rawBmp.height - dim) / 2
                        val square = android.graphics.Bitmap.createBitmap(rawBmp, xOff, yOff, dim, dim)
                        val sz = dp(88)
                        val scaled = android.graphics.Bitmap.createScaledBitmap(square, sz, sz, true)
                        val circular = android.graphics.Bitmap.createBitmap(sz, sz, android.graphics.Bitmap.Config.ARGB_8888)
                        val canvas = android.graphics.Canvas(circular)
                        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
                        paint.shader = android.graphics.BitmapShader(scaled, android.graphics.Shader.TileMode.CLAMP, android.graphics.Shader.TileMode.CLAMP)
                        canvas.drawCircle(sz / 2f, sz / 2f, sz / 2f, paint)
                        paint.shader = null
                        paint.style = android.graphics.Paint.Style.STROKE
                        paint.strokeWidth = dp(3).toFloat()
                        paint.color = Color.BLACK
                        canvas.drawCircle(sz / 2f, sz / 2f, sz / 2f - dp(2).toFloat(), paint)
                        Handler(Looper.getMainLooper()).post {
                            avatarView.background = null
                            avatarView.setImageBitmap(circular)
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Profile photo load failed: ${e.message}")
                }
            }.start()
        }

        // ── Lock icon (tap 10× for emergency PIN)
        var tapCount = 0
        val iconSize = dp(100)
        val iconFrame = FrameLayout(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(iconSize, iconSize).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        }
        iconFrame.addView(View(ctx).apply {
            layoutParams = FrameLayout.LayoutParams(iconSize, iconSize)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setStroke(dp(3), Color.BLACK)
                setColor(Color.TRANSPARENT)
            }
        })
        iconFrame.addView(TextView(ctx).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER }
            text = "🔒"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 46f)
        })
        iconFrame.isClickable = true
        iconFrame.isFocusable = true
        iconFrame.setOnClickListener {
            tapCount++
            tapResetHandler.removeCallbacks(tapResetRunnable)
            tapResetHandler.postDelayed(tapResetRunnable, 5000)
            if (tapCount >= 10) { tapCount = 0; showEmergencyPinPanel(root) }
        }
        content.addView(iconFrame)
        content.addView(spacer(20))

        // ── LOCKED headline
        content.addView(TextView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            text = (prefs.getString("lockHeadline", "LOCKED") ?: "LOCKED").uppercase()
            setTextColor(Color.BLACK)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 40f)
            setTypeface(null, Typeface.BOLD)
            letterSpacing = 0.15f
            gravity = Gravity.CENTER
        })
        content.addView(spacer(20))

        // ── Task box
        val taskTitle = prefs.getString("taskTitle", "") ?: ""
        val taskItems = prefs.getString("taskList", "") ?: ""
        val fallback  = prefs.getString("lockMessage",
            "This device is temporarily locked.\nComplete your tasks to unlock.") ?: ""

        val taskBox = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            background = GradientDrawable().apply {
                cornerRadius = dp(18).toFloat(); setColor(Color.TRANSPARENT)
                setStroke(dp(2), Color.BLACK)
            }
            setPadding(dp(18), dp(18), dp(18), dp(18))
        }
        taskBox.addView(TextView(ctx).apply {
            text = (if (taskTitle.isNotEmpty()) taskTitle else "YOUR TASKS").uppercase()
            setTextColor(Color.BLACK)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTypeface(null, Typeface.BOLD)
            letterSpacing = 0.12f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        })
        if (taskItems.isNotEmpty()) {
            taskBox.addView(spacer(12))
            taskItems.split("\n").forEach { line ->
                val clean = line.replace(Regex("^\\s*[•\\-*]\\s*"), "").trim()
                if (clean.isNotEmpty()) taskBox.addView(TextView(ctx).apply {
                    text = clean.uppercase()
                    setTextColor(Color.BLACK)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    setTypeface(null, Typeface.BOLD)
                    gravity = Gravity.CENTER
                    setLineSpacing(dp(2).toFloat(), 1f)
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
                    ).apply { bottomMargin = dp(4) }
                })
            }
        } else {
            taskBox.addView(spacer(8))
            taskBox.addView(TextView(ctx).apply {
                text = fallback
                setTextColor(Color.parseColor("#88000000"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                gravity = Gravity.CENTER
                textAlignment = View.TEXT_ALIGNMENT_CENTER
                setLineSpacing(dp(2).toFloat(), 1f)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            })
        }
        content.addView(taskBox)
        content.addView(spacer(16))

        // ── Action buttons row: MESSAGE | CALL
        val btnRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            weightSum = 2f
        }

        val msgBtn = createActionButton(ctx, "💬", "MESSAGE")
        val smsBtn = createActionButton(ctx, "📲", "SMS")

        (msgBtn.layoutParams as LinearLayout.LayoutParams).apply {
            weight = 1f; width = 0; rightMargin = dp(6)
        }
        (smsBtn.layoutParams as LinearLayout.LayoutParams).apply {
            weight = 1f; width = 0; leftMargin = dp(6)
        }

        msgBtn.setOnClickListener { showChatPanel(root) }
        smsBtn.setOnClickListener { showSmsPanel(root) }

        btnRow.addView(msgBtn)
        btnRow.addView(smsBtn)
        content.addView(btnRow)
        content.addView(spacer(20))

        // ── Footer hint
        content.addView(TextView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            text = "This device is temporarily locked. Complete\nyour tasks to unlock."
            setTextColor(Color.parseColor("#88000000"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            setLineSpacing(dp(3).toFloat(), 1f)
            gravity = Gravity.CENTER
        })

        scroll.addView(content)
        root.addView(scroll)
        return root
    }

    // ── Action button factory ──────────────────────────────────────────────────

    private fun createActionButton(ctx: Context, emoji: String, label: String): LinearLayout {
        return LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(62))
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(Color.TRANSPARENT)
                setStroke(dp(2), Color.BLACK)
            }
            isClickable  = true
            isFocusable  = true

            addView(TextView(ctx).apply {
                text = emoji
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            })
            addView(TextView(ctx).apply {
                text = label
                setTextColor(Color.BLACK)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
                setTypeface(null, Typeface.BOLD)
                letterSpacing = 0.15f
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            })
        }
    }

    // ── Chat panel ─────────────────────────────────────────────────────────────

    private fun showChatPanel(root: FrameLayout) {
        // Remove any existing panel
        closeActivePanel(root)
        makeFocusable()

        val ctx = this

        // Semi-transparent scrim
        val panel = FrameLayout(ctx).apply {
            tag = "panel"
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
            setBackgroundColor(Color.parseColor("#A8000000"))
            isFocusable = true; isClickable = true
        }

        // Card — full screen floating with 15dp margins on all sides
        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            val lp = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            lp.setMargins(dp(15), dp(15), dp(15), dp(15))
            layoutParams = lp
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(Color.parseColor("#1A1A2E"))
                setStroke(dp(1), Color.parseColor("#40FBBC05"))
            }
            setPadding(0, 0, 0, 0)
        }

        // ── Chat header
        val header = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(56))
            background = GradientDrawable().apply {
                cornerRadii = floatArrayOf(dp(24).toFloat(), dp(24).toFloat(),
                    dp(24).toFloat(), dp(24).toFloat(), 0f, 0f, 0f, 0f)
                setColor(Color.parseColor("#FBBC05"))
            }
            setPadding(dp(16), 0, dp(12), 0)
        }

        header.addView(TextView(ctx).apply {
            text = "💬"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        })
        header.addView(LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                .apply { leftMargin = dp(10) }
            addView(TextView(ctx).apply {
                text = "Message Parent"
                setTextColor(Color.BLACK)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setTypeface(null, Typeface.BOLD)
            })
            addView(TextView(ctx).apply {
                text = "Emergency chat"
                setTextColor(Color.parseColor("#88000000"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            })
        })
        // Close button
        val closeBtn = TextView(ctx).apply {
            text = "✕"
            setTextColor(Color.parseColor("#88000000"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(dp(36), dp(36))
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(Color.parseColor("#22000000"))
            }
            isClickable = true; isFocusable = true
        }
        closeBtn.setOnClickListener {
            chatListener?.remove(); chatListener = null
            closeActivePanel(root)
            makeUnfocusable()
        }
        header.addView(closeBtn)
        card.addView(header)

        // ── Messages scroll area — fills all remaining space between header and input
        val msgScroll = ScrollView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
            setPadding(dp(12), dp(8), dp(12), dp(8))
            isFillViewport = true
        }
        val msgLayout = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        chatMessagesLayout = msgLayout
        chatScrollView = msgScroll

        // Empty state
        val emptyView = TextView(ctx).apply {
            text = "No messages yet.\nSend your parent a message!"
            setTextColor(Color.parseColor("#64748B"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            setLineSpacing(dp(3).toFloat(), 1f)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT)
        }
        msgLayout.addView(emptyView)
        msgScroll.addView(msgLayout)
        card.addView(msgScroll)

        // ── Divider
        card.addView(View(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(1))
            setBackgroundColor(Color.parseColor("#15FFFFFF"))
        })

        // ── Input row
        val inputRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            setPadding(dp(12), dp(8), dp(12), dp(16))
        }

        val inputBox = EditText(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#64748B"))
            hint = "Type a message..."
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            maxLines = 3
            imeOptions = EditorInfo.IME_ACTION_SEND
            background = GradientDrawable().apply {
                cornerRadius = dp(22).toFloat()
                setColor(Color.parseColor("#2D2D44"))
                setStroke(dp(1), Color.parseColor("#40FBBC05"))
            }
            setPadding(dp(14), dp(10), dp(14), dp(10))
        }

        val sendBtn = FrameLayout(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(dp(44), dp(44)).apply { leftMargin = dp(8) }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FBBC05"))
            }
            isClickable = true; isFocusable = true
        }
        sendBtn.addView(TextView(ctx).apply {
            text = "➤"
            setTextColor(Color.BLACK)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        })

        val doSend: () -> Unit = {
            val text = inputBox.text.toString().trim()
            // Resolve deviceId from SharedPreferences if companion var is still empty
            if (overlayDeviceId.isEmpty()) {
                overlayDeviceId = getSharedPreferences("applocker_local_settings", Context.MODE_PRIVATE)
                    .getString("deviceId", "") ?: ""
            }
            if (text.isNotEmpty() && overlayDeviceId.isNotEmpty()) {
                inputBox.text.clear()
                val devId = overlayDeviceId // capture for thread
                Thread {
                    try {
                        com.google.firebase.firestore.FirebaseFirestore.getInstance()
                            .collection("devices")
                            .document(devId)
                            .collection("messages")
                            .add(mapOf(
                                "text" to text,
                                "sender" to "child",
                                "timestamp" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
                                "read" to false
                            ))
                        Log.d(TAG, "Chat message sent: $text")
                    } catch (e: Exception) {
                        Log.e(TAG, "Send chat error: ${e.message}")
                    }
                }.start()
            } else if (overlayDeviceId.isEmpty()) {
                Log.w(TAG, "doSend: overlayDeviceId is empty, cannot send message")
            }
        }

        sendBtn.setOnClickListener { doSend() }
        inputBox.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) { doSend(); true } else false
        }

        inputRow.addView(inputBox)
        inputRow.addView(sendBtn)
        card.addView(inputRow)

        panel.addView(card)
        root.addView(panel)
        attachKeyboardLift(root, card, dp(15), dp(15), dp(15), dp(15))

        // Request focus on input box + show keyboard after layout settles
        inputBox.postDelayed({
            inputBox.requestFocus()
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
            imm.showSoftInput(inputBox, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
        }, 250)

        // ── Start Firestore listener for messages
        startChatListener(msgLayout, emptyView, msgScroll)
    }

    private fun startChatListener(
        msgLayout: LinearLayout,
        emptyView: TextView,
        scroll: ScrollView
    ) {
        // Ensure we have a deviceId — load from SharedPreferences if still empty
        if (overlayDeviceId.isEmpty()) {
            overlayDeviceId = getSharedPreferences("applocker_local_settings", Context.MODE_PRIVATE)
                .getString("deviceId", "") ?: ""
        }
        if (overlayDeviceId.isEmpty()) {
            Log.w(TAG, "startChatListener: overlayDeviceId is empty, cannot listen")
            return
        }
        chatListener?.remove()
        chatListener = com.google.firebase.firestore.FirebaseFirestore.getInstance()
            .collection("devices")
            .document(overlayDeviceId)
            .collection("messages")
            .orderBy("timestamp", com.google.firebase.firestore.Query.Direction.ASCENDING)
            .addSnapshotListener { snapshot, error ->
                if (error != null) { Log.e(TAG, "Chat listener error: ${error.message}"); return@addSnapshotListener }
                val docs = snapshot?.documents ?: return@addSnapshotListener
                Handler(Looper.getMainLooper()).post {
                    msgLayout.removeAllViews()
                    if (docs.isEmpty()) {
                        msgLayout.addView(emptyView)
                    } else {
                        docs.forEach { doc ->
                            val text     = doc.getString("text") ?: return@forEach
                            val isChild  = doc.getString("sender") == "child"
                            val ts       = doc.getTimestamp("timestamp")
                            val timeStr  = if (ts != null) formatTime(ts.toDate()) else ""
                            msgLayout.addView(buildMessageBubble(text, isChild, timeStr))
                        }
                        scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
                    }
                }
            }
    }

    private fun buildMessageBubble(text: String, isChild: Boolean, timeStr: String): LinearLayout {
        val ctx = this
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = if (isChild) Gravity.END else Gravity.START
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(8) }
        }

        val col = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        }

        // Bubble
        val bubbleBg = GradientDrawable().apply {
            if (isChild) {
                cornerRadii = floatArrayOf(dp(16).toFloat(), dp(16).toFloat(),
                    dp(16).toFloat(), dp(16).toFloat(),
                    dp(4).toFloat(), dp(4).toFloat(),
                    dp(16).toFloat(), dp(16).toFloat())
                setColor(Color.parseColor("#FBBC05"))
            } else {
                cornerRadii = floatArrayOf(dp(16).toFloat(), dp(16).toFloat(),
                    dp(16).toFloat(), dp(16).toFloat(),
                    dp(16).toFloat(), dp(16).toFloat(),
                    dp(4).toFloat(), dp(4).toFloat())
                setColor(Color.parseColor("#2D2D44"))
            }
        }
        col.addView(TextView(ctx).apply {
            this.text = text
            setTextColor(if (isChild) Color.BLACK else Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTypeface(null, Typeface.BOLD)
            background = bubbleBg
            setPadding(dp(12), dp(9), dp(12), dp(9))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        })

        if (timeStr.isNotEmpty()) col.addView(TextView(ctx).apply {
            this.text = timeStr
            setTextColor(Color.parseColor("#64748B"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)
            gravity = if (isChild) Gravity.END else Gravity.START
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(2) }
        })

        row.addView(col)
        return row
    }

    // ── SMS panel ──────────────────────────────────────────────────────────────

    private fun showSmsPanel(root: FrameLayout) {
        closeActivePanel(root)
        makeFocusable()

        val ctx = this
        val prefs = getSharedPreferences("applocker_local_settings", Context.MODE_PRIVATE)
        val receiverNumber = prefs.getString("smsReceiverNumber", "") ?: ""

        val panel = FrameLayout(ctx).apply {
            tag = "panel"
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
            setBackgroundColor(Color.parseColor("#A8000000"))
            isFocusable = true; isClickable = true
        }

        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            val lp = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            lp.setMargins(dp(15), dp(15), dp(15), dp(15))
            layoutParams = lp
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(Color.parseColor("#1A1A2E"))
                setStroke(dp(1), Color.parseColor("#40FBBC05"))
            }
            setPadding(dp(18), dp(16), dp(18), dp(16))
        }

        // ── Header
        val header = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        header.addView(FrameLayout(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(dp(36), dp(36))
            background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat()
                setColor(Color.parseColor("#25FBBC05"))
            }
            addView(TextView(ctx).apply {
                text = "📲"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                gravity = Gravity.CENTER
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
            })
        })
        val headerText = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { leftMargin = dp(10) }
        }
        headerText.addView(TextView(ctx).apply {
            text = "Send SMS"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTypeface(null, Typeface.BOLD)
        })
        val numLabel = if (receiverNumber.isNotEmpty()) "To: $receiverNumber" else "No number configured in admin"
        headerText.addView(TextView(ctx).apply {
            text = numLabel
            setTextColor(Color.parseColor("#94A3B8"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        })
        header.addView(headerText)
        val closeSmsBtn = TextView(ctx).apply {
            text = "✕"
            setTextColor(Color.parseColor("#66FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(dp(30), dp(30))
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(Color.parseColor("#15FFFFFF"))
            }
            isClickable = true; isFocusable = true
        }
        closeSmsBtn.setOnClickListener { closeActivePanel(root); makeUnfocusable() }
        header.addView(closeSmsBtn)
        card.addView(header)
        card.addView(spacer(16))

        card.addView(TextView(ctx).apply {
            text = "Use this only when you need help while the phone is locked."
            setTextColor(Color.parseColor("#94A3B8"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setLineSpacing(dp(3).toFloat(), 1f)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        })
        card.addView(spacer(12))

        // ── Message input
        val msgInput = EditText(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#64748B"))
            hint = "Type your message..."
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            minLines = 6
            gravity = Gravity.TOP or Gravity.START
            background = GradientDrawable().apply {
                cornerRadius = dp(14).toFloat()
                setColor(Color.parseColor("#2D2D44"))
                setStroke(dp(1), Color.parseColor("#40FBBC05"))
            }
            setPadding(dp(14), dp(12), dp(14), dp(12))
        }
        card.addView(msgInput)
        card.addView(spacer(12))

        // ── Status label (shows success/error feedback)
        val statusTv = TextView(ctx).apply {
            text = ""
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { bottomMargin = dp(10) }
        }
        card.addView(statusTv)

        // ── SEND button
        val sendSmsBtn = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(52))
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(if (receiverNumber.isNotEmpty()) Color.parseColor("#FBBC05") else Color.parseColor("#374151"))
            }
            isClickable = receiverNumber.isNotEmpty()
            isFocusable = receiverNumber.isNotEmpty()
        }
        sendSmsBtn.addView(TextView(ctx).apply {
            text = if (receiverNumber.isNotEmpty()) "📲  SEND SMS" else "⚙️  Configure number in Admin"
            setTextColor(if (receiverNumber.isNotEmpty()) Color.BLACK else Color.parseColor("#9CA3AF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(null, Typeface.BOLD)
            letterSpacing = 0.1f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        })
        if (receiverNumber.isNotEmpty()) {
            sendSmsBtn.setOnClickListener {
                val msg = msgInput.text.toString().trim()
                if (msg.isEmpty()) {
                    statusTv.text = "Please type a message first."
                    statusTv.setTextColor(Color.parseColor("#F87171"))
                    statusTv.visibility = View.VISIBLE
                    return@setOnClickListener
                }
                try {
                    @Suppress("DEPRECATION")
                    val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                        getSystemService(android.telephony.SmsManager::class.java)
                    else android.telephony.SmsManager.getDefault()
                    val parts = smsManager.divideMessage(msg)
                    smsManager.sendMultipartTextMessage(receiverNumber, null, parts, null, null)
                    msgInput.text.clear()
                    statusTv.text = "✓ SMS sent to $receiverNumber"
                    statusTv.setTextColor(Color.parseColor("#4ADE80"))
                    statusTv.visibility = View.VISIBLE
                    statusTv.postDelayed({ closeActivePanel(root); makeUnfocusable() }, 1500)
                    Log.d(TAG, "SMS sent to $receiverNumber")
                } catch (e: Exception) {
                    statusTv.text = "Failed to send SMS: ${e.message}"
                    statusTv.setTextColor(Color.parseColor("#F87171"))
                    statusTv.visibility = View.VISIBLE
                    Log.e(TAG, "SMS send error: ${e.message}")
                }
            }
        }
        card.addView(sendSmsBtn)

        panel.addView(card)
        root.addView(panel)
        attachKeyboardLift(root, card, dp(15), dp(15), dp(15), dp(15))

        closeSmsBtn.setOnClickListener {
            closeActivePanel(root); makeUnfocusable()
        }

        // Show keyboard
        msgInput.postDelayed({
            msgInput.requestFocus()
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showSoftInput(msgInput, InputMethodManager.SHOW_IMPLICIT)
        }, 200)
    }

    // ── Emergency PIN panel ────────────────────────────────────────────────────

    private fun showEmergencyPinPanel(root: FrameLayout) {
        closeActivePanel(root)
        makeFocusable()

        val ctx = this
        val panel = FrameLayout(ctx).apply {
            tag = "panel"
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
            setBackgroundColor(Color.parseColor("#A8000000"))
            isFocusable = true; isClickable = true
        }

        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            val lp = FrameLayout.LayoutParams(dp(280), LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.gravity = Gravity.CENTER
            layoutParams = lp
            background = GradientDrawable().apply {
                cornerRadius = dp(20).toFloat()
                setColor(Color.parseColor("#FFE082"))
                setStroke(dp(2), Color.BLACK)
            }
            setPadding(dp(20), dp(20), dp(20), dp(20))
        }

        card.addView(TextView(ctx).apply {
            text = "🔓  Emergency Unlock"
            setTextColor(Color.BLACK)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTypeface(null, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { bottomMargin = dp(14) }
        })

        val pinInput = EditText(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(54))
            setTextColor(Color.BLACK)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            setTypeface(null, Typeface.BOLD)
            letterSpacing = 0.5f
            gravity = Gravity.CENTER
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
            hint = "· · · · · ·"
            setHintTextColor(Color.parseColor("#66000000"))
            isSingleLine = true
            imeOptions = EditorInfo.IME_ACTION_DONE
            maxEms = 6
            background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat()
                setColor(Color.WHITE)
                setStroke(dp(1), Color.BLACK)
            }
            setPadding(dp(12), dp(8), dp(12), dp(8))
        }

        val errorTv = TextView(ctx).apply {
            text = "INCORRECT PIN"
            setTextColor(Color.RED)
            setTypeface(null, Typeface.BOLD)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            gravity = Gravity.CENTER
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { topMargin = dp(6) }
        }

        pinInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, st: Int, c: Int, a: Int) {}
            override fun onTextChanged(s: CharSequence?, st: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) {
                val t = s?.toString() ?: ""
                if (t.length >= overlayPin.length) {
                    if (t == overlayPin) {
                        closeActivePanel(root)
                        unlockViaFirestore(); notifyFlutterUnlock(); hideOverlay()
                    } else {
                        errorTv.visibility = View.VISIBLE
                        pinInput.text.clear()
                        pinInput.postDelayed({ errorTv.visibility = View.GONE }, 2000)
                    }
                }
            }
        })
        pinInput.setOnClickListener { makeFocusable() }

        val cancelBtn = TextView(ctx).apply {
            text = "CANCEL"
            setTextColor(Color.parseColor("#555555"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(40)).apply { topMargin = dp(10) }
            isClickable = true; isFocusable = true
        }
        cancelBtn.setOnClickListener { closeActivePanel(root); makeUnfocusable() }

        card.addView(pinInput)
        card.addView(errorTv)
        card.addView(cancelBtn)
        panel.addView(card)
        root.addView(panel)
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private fun makeFocusable() {
        try {
            val params = overlayView?.layoutParams as? WindowManager.LayoutParams ?: return
            // Remove FLAG_NOT_FOCUSABLE so keyboard can appear
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            // Remove FLAG_LAYOUT_NO_LIMITS so SOFT_INPUT_ADJUST_RESIZE can shrink the window
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS.inv()
            @Suppress("DEPRECATION")
            params.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE
            windowManager?.updateViewLayout(overlayView, params)
        } catch (e: Exception) { Log.e(TAG, "makeFocusable: ${e.message}") }
    }

    private fun closeActivePanel(root: FrameLayout) {
        clearPanelKeyboardLift()
        root.findViewWithTag<View>("panel")?.let { root.removeView(it) }
    }

    private fun attachKeyboardLift(
        root: View,
        card: View,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int
    ) {
        clearPanelKeyboardLift()
        val listener = ViewTreeObserver.OnGlobalLayoutListener {
            val visible = Rect()
            root.getWindowVisibleDisplayFrame(visible)
            val fullHeight = root.rootView.height
            val keyboardHeight = (fullHeight - visible.bottom).coerceAtLeast(0)
            val effectiveKeyboardHeight = if (keyboardHeight > dp(80)) keyboardHeight else 0
            val params = card.layoutParams as? FrameLayout.LayoutParams ?: return@OnGlobalLayoutListener
            val nextBottom = bottom + effectiveKeyboardHeight
            if (params.leftMargin != left || params.topMargin != top ||
                params.rightMargin != right || params.bottomMargin != nextBottom) {
                params.setMargins(left, top, right, nextBottom)
                card.layoutParams = params
                chatScrollView?.post { chatScrollView?.fullScroll(View.FOCUS_DOWN) }
            }
        }
        panelKeyboardRoot = root
        panelKeyboardListener = listener
        root.viewTreeObserver.addOnGlobalLayoutListener(listener)
    }

    private fun clearPanelKeyboardLift() {
        val root = panelKeyboardRoot
        val listener = panelKeyboardListener
        if (root != null && listener != null && root.viewTreeObserver.isAlive) {
            root.viewTreeObserver.removeOnGlobalLayoutListener(listener)
        }
        panelKeyboardRoot = null
        panelKeyboardListener = null
    }

    private fun makeUnfocusable() {
        try {
            val params = overlayView?.layoutParams as? WindowManager.LayoutParams ?: return
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            // Restore FLAG_LAYOUT_NO_LIMITS for edge-to-edge lock screen
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            params.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_STATE_HIDDEN
            windowManager?.updateViewLayout(overlayView, params)
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.hideSoftInputFromWindow(overlayView?.windowToken, 0)
        } catch (e: Exception) { Log.e(TAG, "makeUnfocusable: ${e.message}") }
    }

    private fun unlockViaFirestore() {
        if (overlayDeviceId.isEmpty()) return
        Thread {
            try {
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("devices").document(overlayDeviceId)
                    .update(mapOf(
                        "locked" to false,
                        "pendingCommand" to com.google.firebase.firestore.FieldValue.delete()
                    ))
            } catch (e: Exception) { Log.e(TAG, "Firestore unlock: ${e.message}") }
        }.start()
    }

    private fun notifyFlutterUnlock() {
        try {
            val prefs = getSharedPreferences("lock_state", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("locked", false).apply()
            sendBroadcast(Intent("com.parentalcontrol.UNLOCK_EVENT"))
        } catch (e: Exception) { Log.e(TAG, "notifyFlutterUnlock: ${e.message}") }
    }

    private fun formatTime(dt: java.util.Date): String {
        val cal = java.util.Calendar.getInstance().apply { time = dt }
        val h   = cal.get(java.util.Calendar.HOUR_OF_DAY)
        val m   = cal.get(java.util.Calendar.MINUTE)
        val ampm = if (h >= 12) "PM" else "AM"
        val h12 = if (h == 0) 12 else if (h > 12) h - 12 else h
        return "$h12:${m.toString().padStart(2, '0')} $ampm"
    }

    private fun spacer(dpH: Int) = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(dpH))
    }

    private fun dp(v: Int) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    // ── Service boilerplate ────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Lock Overlay", NotificationManager.IMPORTANCE_LOW)
                .apply { description = "Shows when device is locked by parent"; setShowBadge(false) }
            (getSystemService(NotificationManager::class.java)).createNotificationChannel(ch)
        }
    }

    private fun createNotification() = NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("Device Locked")
        .setContentText("This device is locked.")
        .setSmallIcon(android.R.drawable.ic_lock_lock)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setCategory(Notification.CATEGORY_SERVICE)
        .setOngoing(true).build()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        chatListener?.remove(); chatListener = null
        hideOverlay()
        super.onDestroy()
    }
}
