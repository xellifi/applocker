package com.parentalcontrol.applocker

import android.app.Notification
import android.content.Context
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

/**
 * NotificationInterceptor
 *
 * Intercepts incoming notifications and extracts complete conversation details:
 * - Social messages (incoming + outgoing via MessagingStyle)  → type: "message"
 * - SMS/MMS messages                                          → type: "sms"
 * - Phone call notifications (incoming, missed, outgoing)     → type: "call"
 *
 * Each record includes: sender, receiver, content, direction (isMe), timestamp,
 * app name, and group-chat flag.
 */
class NotificationInterceptor : NotificationListenerService() {

    private var deviceId: String = ""

    // ── Dedup cache ──────────────────────────────────────────────────────────
    // Keep a small in-memory set to avoid writing the same notification twice
    // within a session (SharedPrefs-level dedup handles cross-session.)
    private val recentHashes = LinkedHashSet<String>()

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d("NotificationInterceptor", "Listener Connected")
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
        Log.d("NotificationInterceptor", "deviceId=$deviceId")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (deviceId.isEmpty()) { refreshDeviceId(); if (deviceId.isEmpty()) return }
        if (sbn == null) return
        val notification = sbn.notification ?: return
        val packageName   = sbn.packageName  ?: return
        val extras        = notification.extras ?: return

        // ── STEP 1: Classify the notification source ─────────────────────────
        val lower = packageName.lowercase()

        val isCallApp = lower.contains("telecom")    || lower.contains("telephony") ||
                        lower.contains("dialer")     || lower.contains("incallui")  ||
                        lower.contains("phone")      || packageName == "com.android.server.telecom"

        val isSmsApp  = lower.contains("sms")        || lower.contains("mms")       ||
                        lower.contains("messaging")  ||
                        packageName == "com.android.messaging" ||
                        packageName == "com.google.android.apps.messaging"

        val isSocialApp = lower.contains("messenger") || lower.contains("orca")       ||
                          lower.contains("whatsapp")  || lower.contains("telegram")   ||
                          lower.contains("instagram")  || lower.contains("viber")     ||
                          lower.contains("signal")    || lower.contains("discord")    ||
                          lower.contains("snapchat")  || lower.contains("tiktok")     ||
                          lower.contains("twitter")   || lower.contains("kik")        ||
                          lower.contains("wechat")    || lower.contains("skype")      ||
                          lower.contains("hangouts")  || lower.contains("line")       ||
                          lower.contains("chat")      || lower.contains("message")

        if (!isCallApp && !isSmsApp && !isSocialApp) return

        // ── STEP 2: Skip pure group summaries for social apps ─────────────────
        val isSummary = (notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0
        if (isSummary && !isSmsApp) return

        // ── STEP 3: Route to correct handler ─────────────────────────────────
        when {
            isCallApp   -> handleCallNotification(sbn, extras, packageName)
            isSmsApp    -> handleMessagingNotification(sbn, extras, packageName, type = "sms")
            else        -> handleMessagingNotification(sbn, extras, packageName, type = "message")
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // CALL HANDLER
    // ────────────────────────────────────────────────────────────────────────
    private fun handleCallNotification(
        sbn: StatusBarNotification,
        extras: Bundle,
        packageName: String
    ) {
        val title   = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: "Unknown"
        val text    = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()  ?: ""
        val ticker  = sbn.notification.tickerText?.toString() ?: ""

        // Determine call direction from the notification text
        val combinedText = "$title $text $ticker".lowercase()
        val direction = when {
            combinedText.contains("incoming")  || combinedText.contains("calling in") -> "Incoming Call"
            combinedText.contains("outgoing")  || combinedText.contains("calling")    -> "Outgoing Call"
            combinedText.contains("missed")    || combinedText.contains("missed call") -> "Missed Call"
            combinedText.contains("declined")                                          -> "Declined Call"
            else -> "Call"
        }

        // Caller/callee name is usually in the title for call notifications
        val contactName = title.trim().takeIf { it.isNotEmpty() && it != direction } ?: "Unknown"

        val content = "$direction — $contactName"

        val hash = (packageName + contactName + direction + sbn.postTime.toString()).hashCode().toString()
        if (!shouldSync(hash)) return

        val isIncoming = direction.startsWith("Incoming")
        val isMissed   = direction.startsWith("Missed")

        val data = hashMapOf(
            "type"               to "call",
            "packageName"        to packageName,
            "appName"            to getAppName(packageName),
            "title"              to contactName,
            "sender"             to if (isIncoming || isMissed) contactName else "Me",
            "receiver"           to if (isIncoming || isMissed) "Me"        else contactName,
            "direction"          to direction,
            "content"            to content,
            "isMe"               to (!isIncoming && !isMissed),
            "isGroupConversation" to false,
            "msgTimestamp"       to sbn.postTime,
            "timestamp"          to FieldValue.serverTimestamp(),
            "deviceId"           to deviceId
        )

        val docId = "${deviceId}_$hash"
        FirebaseFirestore.getInstance()
            .collection("devices").document(deviceId)
            .collection("activity").document(docId).set(data)
            .addOnSuccessListener { Log.d("NotificationInterceptor", "Call logged: $direction $contactName") }
            .addOnFailureListener { e -> Log.e("NotificationInterceptor", "Call sync failed: ${e.message}") }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SMS / SOCIAL MESSAGE HANDLER
    // ────────────────────────────────────────────────────────────────────────
    private fun handleMessagingNotification(
        sbn: StatusBarNotification,
        extras: Bundle,
        packageName: String,
        type: String
    ) {
        val isMessagingStyle = extras.getString(Notification.EXTRA_TEMPLATE)
            ?.contains("MessagingStyle") == true

        // Thread / conversation name
        val conversationTitle = extras.getString("android.conversationTitle")
            ?: extras.getString(Notification.EXTRA_CONVERSATION_TITLE)
        val threadTitle = conversationTitle
            ?: extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            ?: sbn.notification.tickerText?.toString()
            ?: "Unknown"

        var isGroup = extras.getBoolean(Notification.EXTRA_IS_GROUP_CONVERSATION, false)
        if (!isGroup && !conversationTitle.isNullOrEmpty()) isGroup = true

        val collectedMessages = mutableListOf<MsgEntry>()

        // ── A: MessagingStyle — richest data ──────────────────────────────────
        if (isMessagingStyle) {
            val messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
            val historic = extras.getParcelableArray(Notification.EXTRA_HISTORIC_MESSAGES)

            val allMessages = mutableListOf<Parcelable>()
            if (historic != null) allMessages.addAll(historic)
            if (messages  != null) allMessages.addAll(messages)

            for (msgObj in allMessages) {
                val bundle = msgObj as? Bundle ?: continue
                var text = bundle.getCharSequence("text")?.toString()?.trim()
                if (text.isNullOrEmpty()) text = "🖼️ [Media/Attachment]"

                val lowerText = text.lowercase()
                if (lowerText.contains("chat heads") || lowerText.contains("active chat")) continue

                val senderName = bundle.getCharSequence("sender")?.toString()
                    ?: bundle.getParcelable<android.app.Person>("sender_person")?.name?.toString()

                val isMe = senderName == null ||
                           senderName.lowercase() == "me" ||
                           senderName.lowercase() == "you"

                val resolvedSender   = if (isMe) "Me" else (senderName ?: threadTitle)
                val resolvedReceiver = if (isMe) threadTitle else "Me"

                collectedMessages.add(MsgEntry(
                    text       = text,
                    sender     = resolvedSender,
                    receiver   = resolvedReceiver,
                    isMe       = isMe,
                    msgTime    = bundle.getLong("time", System.currentTimeMillis())
                ))
            }
        }

        // ── B: Fallback (plain text notification, common for SMS) ─────────────
        if (collectedMessages.isEmpty()) {
            val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                ?: extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()
                ?: extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
                ?: sbn.notification.tickerText?.toString()

            if (!text.isNullOrEmpty()) {
                val lowerText = text.lowercase()
                if (lowerText.contains("chat heads")          ||
                    lowerText.contains("active chat")         ||
                    lowerText.contains("running in background") ||
                    lowerText.contains("displaying over other apps")) return

                // For SMS: title is the sender's name/number
                val smsSender = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: threadTitle

                collectedMessages.add(MsgEntry(
                    text     = text,
                    sender   = smsSender,
                    receiver = "Me",
                    isMe     = false,
                    msgTime  = sbn.postTime
                ))
            }
        }

        if (collectedMessages.isEmpty()) return

        // ── STEP 4: Persist each message ──────────────────────────────────────
        val appName = getAppName(packageName)
        for (msg in collectedMessages) {
            val hash = (packageName + msg.sender + msg.text + msg.msgTime.toString()).hashCode().toString()
            if (!shouldSync(hash)) continue

            val docId = "${deviceId}_$hash"
            val data = hashMapOf(
                "type"                to type,
                "packageName"         to packageName,
                "appName"             to appName,
                "title"               to threadTitle,
                "sender"              to msg.sender,
                "receiver"            to msg.receiver,
                "isMe"                to msg.isMe,
                "isGroupConversation" to isGroup,
                "content"             to msg.text,
                "msgTimestamp"        to msg.msgTime,
                "timestamp"           to FieldValue.serverTimestamp(),
                "deviceId"            to deviceId
            )

            FirebaseFirestore.getInstance()
                .collection("devices").document(deviceId)
                .collection("activity").document(docId).set(data)
                .addOnSuccessListener {
                    Log.d("NotificationInterceptor",
                        "[$type] ${msg.sender} → ${msg.receiver}: ${msg.text}")
                }
                .addOnFailureListener { e ->
                    Log.e("NotificationInterceptor", "Sync failed: ${e.message}")
                }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // HELPERS
    // ────────────────────────────────────────────────────────────────────────

    private data class MsgEntry(
        val text: String,
        val sender: String,
        val receiver: String,
        val isMe: Boolean,
        val msgTime: Long
    )

    /**
     * Returns true if this hash has NOT been synced before (allows the write).
     * Uses a 2-tier cache: in-memory LRU + SharedPreferences for persistence.
     */
    private fun shouldSync(hash: String): Boolean {
        if (recentHashes.contains(hash)) return false
        val cachePrefs = getSharedPreferences("msg_cache", Context.MODE_PRIVATE)
        if (cachePrefs.getBoolean(hash, false)) return false
        // Mark as seen
        cachePrefs.edit().putBoolean(hash, true).apply()
        recentHashes.add(hash)
        // Keep in-memory cache bounded
        if (recentHashes.size > 500) recentHashes.iterator().let { it.next(); it.remove() }
        return true
    }

    private fun getAppName(packageName: String): String {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) { packageName }
    }
}
