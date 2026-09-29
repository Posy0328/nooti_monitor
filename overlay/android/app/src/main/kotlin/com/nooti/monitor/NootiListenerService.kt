package com.nooti.monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

/**
 * 通知监听服务：拿到「通知使用权」后，系统每弹出一条通知都会回调这里。
 *
 * 过滤规则（SharedPreferences 里的 JSON）：
 *   enabled  = 总开关
 *   groups   = 「安静群组」名单（通知标题包含其中任意一段即命中）
 *   keywords = 「重点词」名单（标题+正文包含即命中）
 *
 * 命中逻辑（只影响命中规则的群，个人私聊一律不碰）：
 *   安静群 + 含重点词 → 吞掉原通知，改由 Nooti 发高优先级的「重点提醒」
 *   安静群 + 无重点词 → 吞掉原通知（不响不弹），仅记录在列表里
 *   其他              → 不动，只记录
 */
class NootiListenerService : NotificationListenerService() {

    override fun onCreate() {
        super.onCreate()
        ensureChannels()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val n = sbn.notification ?: return
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        // 系统级静默标记（渠道重要级别低，只是不响，通知仍进通知栏）
        var silent = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val nm = getSystemService(NotificationManager::class.java)
                val ch = nm?.getNotificationChannel(n.channelId)
                if (ch != null && ch.importance <= NotificationManager.IMPORTANCE_LOW) silent = true
            } catch (_: Exception) {
            }
        }

        // 按用户规则过滤
        var muted = false
        var alerted = false
        try {
            val raw = getSharedPreferences("nooti_rules", Context.MODE_PRIVATE)
                .getString("rules", "") ?: ""
            if (raw.isNotEmpty()) {
                val rules = JSONObject(raw)
                val enabled = rules.optBoolean("enabled", false)
                if (enabled && sbn.packageName != packageName) {
                    var quiet = false
                    val groups = rules.optJSONArray("groups")
                    if (groups != null) {
                        for (i in 0 until groups.length()) {
                            val g = groups.optString(i, "")
                            if (g.isNotBlank() && title.contains(g, ignoreCase = true)) {
                                quiet = true
                                break
                            }
                        }
                    }
                    var hit = false
                    val keywords = rules.optJSONArray("keywords")
                    if (keywords != null) {
                        val full = "$title $text"
                        for (i in 0 until keywords.length()) {
                            val k = keywords.optString(i, "")
                            if (k.isNotBlank() && full.contains(k, ignoreCase = true)) {
                                hit = true
                                break
                            }
                        }
                    }
                    if (quiet && hit) {
                        muted = true
                        alerted = true
                        try { cancelNotification(sbn.key) } catch (_: Exception) {}
                        postAlert(title, text)
                    } else if (quiet) {
                        muted = true
                        try { cancelNotification(sbn.key) } catch (_: Exception) {}
                    }
                }
            }
        } catch (_: Exception) {
        }

        val item = HashMap<String, Any>()
        item["pkg"] = sbn.packageName ?: ""
        item["title"] = title
        item["text"] = text
        item["time"] = sbn.postTime
        item["silent"] = silent
        item["muted"] = muted
        item["alerted"] = alerted
        CapturedStore.add(item)
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(
                NotificationChannel("nooti_alert", "Nooti 重点提醒", NotificationManager.IMPORTANCE_HIGH)
            )
        }
    }

    // 发 Nooti 自己的高优先级提醒（会响会弹横幅）
    private fun postAlert(title: String, text: String) {
        try {
            ensureChannels()
            val pi = PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, "nooti_alert")
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
            }
            val notif = builder
                .setContentTitle("重要消息 · $title")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build()
            val nm = getSystemService(NotificationManager::class.java)
            nm?.notify((System.currentTimeMillis() % 1000000).toInt(), notif)
        } catch (_: Exception) {
        }
    }
}
