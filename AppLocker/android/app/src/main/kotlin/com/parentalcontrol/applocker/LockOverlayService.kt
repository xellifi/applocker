package com.parentalcontrol.applocker

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
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
            val action = intent?.getStringExtra("action") ?: "show"
            val pin   = intent?.getStringExtra("pin")
            val devId = intent?.getStringExtra("deviceId")
            if (pin   != null) overlayPin      = pin
            if (devId != null) overlayDeviceId = devId
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
        iconFrame.setOnClickListener {
            tapCount++
            tapResetHandler.removeCallbacks(tapResetRunnable)
            tapResetHandler.postDelayed(tapResetRunnable, 3000)
            if (tapCount >= 10) { tapCount = 0; showEmergencyPinPanel(root) }
        }
        content.addView(iconFrame)
        content.addView(spacer(20))

        // ── LOCKED headline
        val prefs = getSharedPreferences("applocker_local_settings", Context.MODE_PRIVATE)
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
        val callBtn = createActionButton(ctx, "📞", "CALL")

        (msgBtn.layoutParams as LinearLayout.LayoutParams).apply {
            weight = 1f; width = 0; rightMargin = dp(6)
        }
        (callBtn.layoutParams as LinearLayout.LayoutParams).apply {
            weight = 1f; width = 0; leftMargin = dp(6)
        }

        msgBtn.setOnClickListener  { showChatPanel(root) }
        callBtn.setOnClickListener { showDialerPanel(root) }

        btnRow.addView(msgBtn)
        btnRow.addView(callBtn)
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
        root.findViewWithTag<View>("panel")?.let { root.removeView(it) }
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

        // Card
        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
            background = GradientDrawable().apply {
                cornerRadius = 0f
                setColor(Color.parseColor("#1A1A2E"))
                // Top corners rounded
            }
            val roundBg = GradientDrawable().apply {
                cornerRadii = floatArrayOf(dp(24).toFloat(), dp(24).toFloat(),
                    dp(24).toFloat(), dp(24).toFloat(), 0f, 0f, 0f, 0f)
                setColor(Color.parseColor("#1A1A2E"))
                setStroke(dp(1), Color.parseColor("#40FBBC05"))
            }
            background = roundBg
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
            root.removeView(panel)
            makeUnfocusable()
        }
        header.addView(closeBtn)
        card.addView(header)

        // ── Messages scroll area
        val msgScroll = ScrollView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(280))
            setPadding(dp(12), dp(8), dp(12), dp(8))
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
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            setLineSpacing(dp(3).toFloat(), 1f)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(240))
            gravity = Gravity.CENTER
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
            if (text.isNotEmpty() && overlayDeviceId.isNotEmpty()) {
                inputBox.text.clear()
                Thread {
                    try {
                        com.google.firebase.firestore.FirebaseFirestore.getInstance()
                            .collection("devices")
                            .document(overlayDeviceId)
                            .collection("chat")
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

        // ── Start Firestore listener for messages
        startChatListener(msgLayout, emptyView, msgScroll)
    }

    private fun startChatListener(
        msgLayout: LinearLayout,
        emptyView: TextView,
        scroll: ScrollView
    ) {
        if (overlayDeviceId.isEmpty()) return
        chatListener?.remove()
        chatListener = com.google.firebase.firestore.FirebaseFirestore.getInstance()
            .collection("devices")
            .document(overlayDeviceId)
            .collection("chat")
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

    // ── Dialer panel ───────────────────────────────────────────────────────────

    private fun showDialerPanel(root: FrameLayout) {
        root.findViewWithTag<View>("panel")?.let { root.removeView(it) }

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
            val lp = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
            layoutParams = lp
            background = GradientDrawable().apply {
                cornerRadii = floatArrayOf(dp(24).toFloat(), dp(24).toFloat(),
                    dp(24).toFloat(), dp(24).toFloat(), 0f, 0f, 0f, 0f)
                setColor(Color.parseColor("#1A1A2E"))
                setStroke(dp(1), Color.parseColor("#40FBBC05"))
            }
            setPadding(dp(20), dp(16), dp(20), dp(20))
        }

        // ── Dialer header
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
                text = "📞"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                gravity = Gravity.CENTER
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
            })
        })
        header.addView(TextView(ctx).apply {
            text = "Emergency Call"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTypeface(null, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { leftMargin = dp(10) }
        })
        val closeBtn2 = TextView(ctx).apply {
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
        closeBtn2.setOnClickListener { root.removeView(panel); makeUnfocusable() }
        header.addView(closeBtn2)
        card.addView(header)
        card.addView(spacer(16))

        // ── Number display
        var numberStr = ""
        val numberDisplay = TextView(ctx).apply {
            text = "Enter number..."
            setTextColor(Color.parseColor("#64748B"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            setTypeface(null, Typeface.BOLD)
            letterSpacing = 0.15f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(56))
            background = GradientDrawable().apply {
                cornerRadius = dp(14).toFloat()
                setColor(Color.parseColor("#2D2D44"))
                setStroke(dp(1), Color.parseColor("#20FBBC05"))
            }
        }
        card.addView(numberDisplay)
        card.addView(spacer(14))

        fun updateDisplay() {
            if (numberStr.isEmpty()) {
                numberDisplay.text = "Enter number..."
                numberDisplay.setTextColor(Color.parseColor("#64748B"))
                numberDisplay.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            } else {
                numberDisplay.text = numberStr
                numberDisplay.setTextColor(Color.WHITE)
                numberDisplay.setTextSize(TypedValue.COMPLEX_UNIT_SP,
                    if (numberStr.length > 10) 20f else 24f)
            }
        }

        // ── Dialpad rows
        val dialRows = listOf(
            listOf("1", "2", "3"),
            listOf("4", "5", "6"),
            listOf("7", "8", "9"),
            listOf("*", "0", "#")
        )
        dialRows.forEach { row ->
            val rowLayout = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, dp(54)).apply { bottomMargin = dp(10) }
                weightSum = 3f
            }
            row.forEach { digit ->
                val key = TextView(ctx).apply {
                    text = digit
                    setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
                    setTypeface(null, Typeface.BOLD)
                    gravity = Gravity.CENTER
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f)
                        .apply { if (digit != "#") rightMargin = dp(10) }
                    background = GradientDrawable().apply {
                        cornerRadius = dp(14).toFloat()
                        setColor(Color.parseColor("#2D2D44"))
                        setStroke(dp(1), Color.parseColor("#10FFFFFF"))
                    }
                    isClickable = true; isFocusable = true
                }
                key.setOnClickListener {
                    if (numberStr.length < 15) {
                        numberStr += digit
                        updateDisplay()
                    }
                }
                rowLayout.addView(key)
            }
            card.addView(rowLayout)
        }

        // Backspace row
        val bsRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { bottomMargin = dp(8) }
            gravity = Gravity.END
        }
        bsRow.addView(TextView(ctx).apply {
            text = "⌫  Clear"
            setTextColor(Color.parseColor("#94A3B8"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTypeface(null, Typeface.BOLD)
            isClickable = true; isFocusable = true
            setOnClickListener { numberStr = ""; updateDisplay() }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        })
        card.addView(bsRow)

        // ── CALL button
        val callBtn = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(54))
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(Color.parseColor("#22C55E"))
            }
            isClickable = true; isFocusable = true
        }
        callBtn.addView(TextView(ctx).apply {
            text = "📞  CALL"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            setTypeface(null, Typeface.BOLD)
            letterSpacing = 0.15f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        })
        callBtn.setOnClickListener {
            if (numberStr.isNotEmpty()) {
                try {
                    val dialIntent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$numberStr"))
                    dialIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(dialIntent)
                } catch (e: Exception) {
                    Log.e(TAG, "DIAL intent failed: ${e.message}")
                }
            }
        }
        card.addView(callBtn)
        panel.addView(card)
        root.addView(panel)
    }

    // ── Emergency PIN panel ────────────────────────────────────────────────────

    private fun showEmergencyPinPanel(root: FrameLayout) {
        root.findViewWithTag<View>("panel")?.let { root.removeView(it) }
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
                        root.removeView(panel)
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
        cancelBtn.setOnClickListener { root.removeView(panel); makeUnfocusable() }

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
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            windowManager?.updateViewLayout(overlayView, params)
        } catch (e: Exception) { Log.e(TAG, "makeFocusable: ${e.message}") }
    }

    private fun makeUnfocusable() {
        try {
            val params = overlayView?.layoutParams as? WindowManager.LayoutParams ?: return
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
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
