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
import org.json.JSONArray
import org.json.JSONObject

/**
 * 通知监听服务：拿到「通知使用权」后，系统每弹出一条通知都会回调这里。
 *
 * v4 能力：
 *  1) 过滤规则（SharedPreferences "nooti_rules"）：
 *     enabled/groups/keywords —— 安静群吞通知，含重点词时改发全屏强提醒；
 *     个人私聊一律不碰。
 *  2) 自动发现（"discovered"）：记下微信/QQ里出现过消息的对话标题，
 *     按「发送者: 内容」格式粗判是不是群，供界面一键「设为安静」。
 *  3) 重点提醒升级为全屏弹窗（setFullScreenIntent，像来电一样）。
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

        // 记住出现过的群/联系人（供用户一键设为安静）
        recordDiscovered(sbn.packageName, title, text)

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

    // 把微信/QQ里出现过消息的对话标题记下来（标题去重，最多留 60 条）
    private fun recordDiscovered(pkg: String, title: String, text: String) {
        if (title.isBlank()) return
        if (pkg != "com.tencent.mm" && pkg != "com.tencent.mobileqq") return
        try {
            val prefs = getSharedPreferences("nooti_rules", Context.MODE_PRIVATE)
            val arr = JSONArray(prefs.getString("discovered", "[]") ?: "[]")
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                if (o.optString("pkg") == pkg && o.optString("t") == title) return
            }
            // 群消息的正文一般是「发送者: 内容」，私聊则没有发送者前缀——粗判群/私聊
            val groupish = Regex("^[^\\s:：]{1,12}[:：].+").containsMatchIn(text)
            val o = JSONObject()
            o.put("pkg", pkg)
            o.put("t", title)
            o.put("g", groupish)
            o.put("ts", System.currentTimeMillis())
            arr.put(o)
            while (arr.length() > 60) arr.remove(0)
            prefs.edit().putString("discovered", arr.toString()).apply()
        } catch (_: Exception) {
        }
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(
                NotificationChannel("nooti_alert", "Nooti 重点提醒", NotificationManager.IMPORTANCE_HIGH)
            )
        }
    }

    // 发 Nooti 自己的强提醒：高优先级 + 全屏弹窗（像来电一样，锁屏/其他App上都会弹）
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
                .setFullScreenIntent(pi, true)
                .setCategory(Notification.CATEGORY_ALARM)
                .setAutoCancel(true)
                .build()
            val nm = getSystemService(NotificationManager::class.java)
            nm?.notify((System.currentTimeMillis() % 1000000).toInt(), notif)
        } catch (_: Exception) {
        }
    }
}
