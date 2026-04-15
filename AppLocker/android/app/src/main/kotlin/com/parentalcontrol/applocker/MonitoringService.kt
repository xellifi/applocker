package com.parentalcontrol.applocker

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.google.firebase.FirebaseApp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import java.util.*

/**
 * MonitoringService
 *
 * An Accessibility Service that tracks:
 * 1. App Opens (App Opened tab)  — type: "app_usage"
 * 2. Web Browser URLs            — type: "url"
 * 3. Outgoing Social Messages    — type: "message" (social apps) or "sms" (native SMS)
 *
 * Data is synced to Firestore under devices/{deviceId}/activity
 */
class MonitoringService : AccessibilityService() {

    private var deviceId: String = ""
    private var lastUrl: String? = null

    // App usage tracking
    private var currentPackage: String? = null
    private var currentAppStartTime: Long = 0L
    // Debounce: don't log the same app open twice within 2 seconds
    private var lastLoggedPackage: String? = null
    private var lastLoggedTime: Long = 0L

    // Per-package URL debounce
    private val lastSyncTimePerPkg = mutableMapOf<String, Long>()
    private val urlSyncInterval = 3000L // 3 sec per URL

    // Outgoing message tracking
    private var lastTypedText: String = ""
    private var lastTypedTime: Long = 0L
    private var lastMsgSyncHash: Int = 0

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("MonitoringService", "Service Connected")
        if (FirebaseApp.getApps(this).isEmpty()) FirebaseApp.initializeApp(this)
        refreshDeviceId()
    }

    private fun refreshDeviceId() {
        val sharedPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        deviceId = sharedPrefs.getString("flutter.deviceId", "") ?: ""
        if (deviceId.isEmpty()) {
            val localPrefs = getSharedPreferences("applocker_local_settings", Context.MODE_PRIVATE)
            deviceId = localPrefs.getString("device_id", "") ?: ""
        }
        if (deviceId.isNotEmpty()) {
            Log.d("MonitoringService", "Monitoring active for deviceId: $deviceId")
        } else {
            Log.w("MonitoringService", "Device ID is empty. Monitoring might not sync.")
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (deviceId.isEmpty()) { refreshDeviceId(); if (deviceId.isEmpty()) return }

        val pkg = event.packageName?.toString() ?: currentPackage ?: ""

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                handlePackageChange(pkg)
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                handleContentChange(event)
            }
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                val node = event.source ?: return
                if (node.className == "android.widget.EditText") {
                    val newText = event.text.joinToString("").trim()
                    if (newText.isNotEmpty()) {
                        lastTypedText = newText
                        lastTypedTime = System.currentTimeMillis()
                    } else if (newText.isEmpty() && lastTypedText.isNotEmpty() && lastTypedText.length > 1) {
                        // EditText cleared suddenly → message was likely SENT
                        if (isMessagingApp(pkg) && lastTypedText.hashCode() != lastMsgSyncHash) {
                            syncOutgoingMessage(lastTypedText, pkg)
                            lastMsgSyncHash = lastTypedText.hashCode()
                        }
                        lastTypedText = ""
                    }
                }
            }
            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                val node = event.source ?: return
                val isEditText = node.className == "android.widget.EditText"
                if (!isEditText && lastTypedText.isNotEmpty() && lastTypedText.length > 1) {
                    val now = System.currentTimeMillis()
                    // If they clicked something (like Send) within 15 seconds of typing
                    if (now - lastTypedTime < 15000L) {
                        if (isMessagingApp(pkg) && lastTypedText.hashCode() != lastMsgSyncHash) {
                            syncOutgoingMessage(lastTypedText, pkg)
                            lastMsgSyncHash = lastTypedText.hashCode()
                        }
                        lastTypedText = ""
                    }
                }
            }
        }
    }

    private fun isMessagingApp(pkg: String): Boolean {
        val lower = pkg.lowercase()
        return lower.contains("messenger")   || lower.contains("orca")       ||
               lower.contains("message")    || lower.contains("sms")        || lower.contains("mms")  ||
               lower.contains("whatsapp")   || lower.contains("telegram")   ||
               lower.contains("instagram")  || lower.contains("viber")      ||
               lower.contains("signal")     || lower.contains("discord")    ||
               lower.contains("snapchat")   || lower.contains("tiktok")     ||
               lower.contains("twitter")    || lower.contains("x.com")      ||
               lower.contains("line")       || lower.contains("kik")        ||
               lower.contains("wechat")     || lower.contains("skype")      ||
               lower.contains("hangouts")   || lower.contains("chat")
    }

    private fun handlePackageChange(packageName: String) {
        // Ignore ourselves and system UI
        if (packageName == this.packageName) return
        if (packageName == "com.android.systemui") return
        if (packageName == "android") return
        if (packageName.isEmpty()) return

        val now = System.currentTimeMillis()

        // ── Log previous app session duration when switching away ─────────────────
        val prev = currentPackage
        if (prev != null && prev != packageName && currentAppStartTime > 0L) {
            val durationMs = now - currentAppStartTime
            // Only log if at least 1 second of usage
            if (durationMs >= 1000L) {
                syncAppSession(prev, durationMs)
            }
        }

        // ── Log the new app as an OPEN event immediately ─────────────────────────
        // Debounce: skip if same app within 2 seconds (avoids double-fire from
        // TYPE_WINDOW_STATE_CHANGED + activity transitions).
        val isSameRecentApp = packageName == lastLoggedPackage && (now - lastLoggedTime) < 2000L
        if (!isSameRecentApp && packageName != currentPackage) {
            syncAppOpen(packageName)
            lastLoggedPackage = packageName
            lastLoggedTime = now
        }

        // ── Start tracking the new app ────────────────────────────────────────────
        if (packageName != currentPackage) {
            currentPackage = packageName
            currentAppStartTime = now
            Log.d("MonitoringService", "App switched to: $packageName")
        }

        // Push realtime 'Active' state to the device document
        syncActiveApp(packageName)
    }

    private fun syncActiveApp(packageName: String) {
        if (deviceId.isEmpty()) { refreshDeviceId(); if (deviceId.isEmpty()) return }

        val pm = packageManager
        var appName = packageName
        try {
            val appInfo = pm.getApplicationInfo(packageName, 0)
            appName = pm.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {}

        val data = hashMapOf(
            "activeApp"      to appName,
            "activePackage"  to packageName,
            "lastActiveTime" to FieldValue.serverTimestamp()
        )

        FirebaseFirestore.getInstance()
            .collection("devices").document(deviceId)
            .update(data as Map<String, Any>)
            .addOnFailureListener {
                 FirebaseFirestore.getInstance().collection("devices").document(deviceId)
                     .set(data, com.google.firebase.firestore.SetOptions.merge())
            }
    }

    /**
     * Logs every individual app-open event.
     * The "App Opened" tab in the dashboard shows these entries,
     * one per each time the child switches to this app.
     */
    private fun syncAppOpen(packageName: String) {
        if (deviceId.isEmpty()) { refreshDeviceId(); if (deviceId.isEmpty()) return }

        val pm = packageManager
        var appName = packageName
        try {
            val appInfo = pm.getApplicationInfo(packageName, 0)
            appName = pm.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {}

        val data = hashMapOf(
            "type"        to "app_usage",  // matches dashboard query
            "packageName" to packageName,
            "appName"     to appName,
            "duration"    to 0L,           // session duration will be updated on close
            "content"     to appName,
            "timestamp"   to FieldValue.serverTimestamp(),
            "deviceId"    to deviceId
        )

        FirebaseFirestore.getInstance()
            .collection("devices").document(deviceId)
            .collection("activity").add(data)
            .addOnSuccessListener { Log.d("MonitoringService", "App opened logged: $appName") }
            .addOnFailureListener { e -> Log.e("MonitoringService", "App open sync failed", e) }
    }

    /**
     * Logs the completed session with duration when the child switches away.
     */
    private fun syncAppSession(packageName: String, durationMs: Long) {
        if (deviceId.isEmpty()) { refreshDeviceId(); if (deviceId.isEmpty()) return }

        val pm = packageManager
        var appName = packageName
        try {
            val appInfo = pm.getApplicationInfo(packageName, 0)
            appName = pm.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {}

        val data = hashMapOf(
            "type"        to "app_usage",  // matches dashboard query
            "packageName" to packageName,
            "appName"     to appName,
            "duration"    to durationMs,   // milliseconds
            "content"     to appName,
            "timestamp"   to FieldValue.serverTimestamp(),
            "deviceId"    to deviceId
        )

        FirebaseFirestore.getInstance()
            .collection("devices").document(deviceId)
            .collection("activity").add(data)
            .addOnSuccessListener { Log.d("MonitoringService", "App session synced: $appName (${durationMs}ms)") }
            .addOnFailureListener { e -> Log.e("MonitoringService", "Session sync failed", e) }
    }

    private fun handleContentChange(event: AccessibilityEvent) {
        val packageName = event.packageName?.toString() ?: return
        val browserPackages = listOf(
            "com.android.chrome", "org.mozilla.firefox",
            "com.sec.android.app.sbrowser", "com.opera.browser",
            "com.brave.browser", "com.microsoft.emmx",
            "com.UCMobile.intl", "com.opera.mini.native",
            "com.android.browser", "com.google.android.browser",
            "com.duckduckgo.mobile.android"
        )
        val isBrowser = browserPackages.any { packageName.startsWith(it) } ||
                        packageName.contains("chrome") ||
                        packageName.contains("browser") ||
                        packageName.contains("firefox")
        if (!isBrowser) return

        val rootNode = rootInActiveWindow ?: return
        val url = findUrl(rootNode)
        if (url != null && url != lastUrl && url.contains(".") && url.length > 4) {
            val now = System.currentTimeMillis()
            val lastSync = lastSyncTimePerPkg[packageName] ?: 0L
            if (now - lastSync < urlSyncInterval) return
            lastSyncTimePerPkg[packageName] = now
            lastUrl = url
            Log.d("MonitoringService", "URL Detected: $url from $packageName")
            syncUrl(url, packageName)
        }
    }

    private fun findUrl(node: AccessibilityNodeInfo?): String? {
        if (node == null) return null
        val resourceId = node.viewIdResourceName
        val urlBarIds = listOf("url_bar", "location_bar", "search_bar",
                               "address_bar", "url_field", "omnibar_text",
                               "mozac_browser_toolbar_url_view")
        if (resourceId != null && urlBarIds.any { resourceId.contains(it) }) {
            val text = node.text?.toString()
            if (!text.isNullOrEmpty() && (text.startsWith("http") || text.contains("."))) return text
        }
        for (i in 0 until node.childCount) {
            val result = findUrl(node.getChild(i))
            if (result != null) return result
        }
        return null
    }

    private fun syncUrl(url: String, packageName: String) {
        if (deviceId.isEmpty()) { refreshDeviceId(); if (deviceId.isEmpty()) return }

        var appName = packageName
        try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            appName = packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {}

        val data = hashMapOf(
            "type"        to "url",
            "content"     to url,
            "packageName" to packageName,
            "appName"     to appName,
            "timestamp"   to FieldValue.serverTimestamp(),
            "deviceId"    to deviceId
        )

        FirebaseFirestore.getInstance()
            .collection("devices").document(deviceId)
            .collection("activity").add(data)
            .addOnSuccessListener { Log.d("MonitoringService", "URL synced: $url") }
            .addOnFailureListener { e -> Log.e("MonitoringService", "URL sync failed", e) }
    }

    /**
     * Walk the accessibility tree to find a recipient/conversation name.
     * Tries standard resource IDs used by common messaging apps.
     */
    private fun extractChatRecipient(node: AccessibilityNodeInfo?): String? {
        if (node == null) return null
        val resId = node.viewIdResourceName?.lowercase() ?: ""

        // Match known title / recipient resource IDs
        val isTitleLike = resId.contains("title") || resId.contains("name")    ||
                          resId.contains("recipient") || resId.contains("contact") ||
                          resId.contains("conversation") || resId.contains("toolbar") ||
                          resId.contains("header") || resId.contains("to_field")

        if (isTitleLike && node.className == "android.widget.TextView" && !node.text.isNullOrEmpty()) {
            val txt = node.text.toString().trim()
            val junkWords = setOf("messenger", "whatsapp", "messages", "chat", "sms", "search",
                                  "back", "ok", "cancel", "send", "attach", "done")
            if (txt.length > 1 && txt.lowercase() !in junkWords) {
                return txt
            }
        }
        for (i in 0 until node.childCount) {
            val res = extractChatRecipient(node.getChild(i))
            if (res != null) return res
        }
        return null
    }

    private fun syncOutgoingMessage(content: String, packageName: String) {
        if (deviceId.isEmpty()) { refreshDeviceId(); if (deviceId.isEmpty()) return }
        if (content.length <= 1) return

        var appName = packageName
        try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            appName = packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {}

        // Try to extract the conversation recipient from the current screen
        val recipient = extractChatRecipient(rootInActiveWindow) ?: appName

        val isSms = packageName.contains("sms")       || packageName.contains("mms")     ||
                    packageName.contains("messaging")  ||
                    packageName == "com.android.messaging" ||
                    packageName == "com.google.android.apps.messaging"

        val type = if (isSms) "sms" else "message"

        val docId = "${deviceId}_${System.currentTimeMillis()}_out"

        val data = hashMapOf(
            "type"                to type,
            "content"             to content,
            "packageName"         to packageName,
            "appName"             to appName,
            "sender"              to "Me",
            "receiver"            to recipient,   // who the child sent the message TO
            "title"               to recipient,   // same — used by dashboard display
            "isMe"                to true,
            "isGroupConversation" to false,
            "msgTimestamp"        to System.currentTimeMillis(),
            "timestamp"           to FieldValue.serverTimestamp(),
            "deviceId"            to deviceId
        )

        FirebaseFirestore.getInstance()
            .collection("devices").document(deviceId)
            .collection("activity").document(docId).set(data)
            .addOnSuccessListener { Log.d("MonitoringService", "Synced outgoing msg to=$recipient: $content") }
            .addOnFailureListener { Log.e("MonitoringService", "Outgoing msg sync failed") }
    }

    override fun onInterrupt() {
        // Flush last app session when service is interrupted
        val now = System.currentTimeMillis()
        val prev = currentPackage
        if (prev != null && currentAppStartTime > 0L) {
            val durationMs = now - currentAppStartTime
            if (durationMs >= 1000L) syncAppSession(prev, durationMs)
        }
        Log.d("MonitoringService", "Interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        // Flush last app session on service destroy
        val now = System.currentTimeMillis()
        val prev = currentPackage
        if (prev != null && currentAppStartTime > 0L) {
            val durationMs = now - currentAppStartTime
            if (durationMs >= 1000L) syncAppSession(prev, durationMs)
        }
    }
}
