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
 * v5 能力：
 *  1) 过滤规则（SharedPreferences "nooti_rules"）：
 *     enabled/groups/keywords/fullscreen —— 安静群吞通知（含清掉它堆积的历史通知），
 *     命中重点词时改发「小卡片」提醒，卡片上带「忽略」「收入待办」两个按钮。
 *     全屏强提醒降级为可选项（默认关）。个人私聊一律不碰。
 *  2) 自动发现（"discovered"）：记下微信/QQ里出现过消息的对话标题，供界面一键「设为安静」。
 *  3) 命中记录带上是哪个词命中的，界面和待办里都能看到。
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
        var hitWord = ""
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
                                hitWord = k
                                break
                            }
                        }
                    }
                    if (quiet && hit) {
                        muted = true
                        alerted = true
                        cancelSameConversation(sbn)
                        postCard(
                            title, text, sbn.packageName ?: "", hitWord,
                            rules.optBoolean("fullscreen", false)
                        )
                    } else if (quiet) {
                        muted = true
                        cancelSameConversation(sbn)
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
        item["kw"] = hitWord
        CapturedStore.add(item)
    }

    /**
     * 静音一条群消息时，把同一个会话此前堆在通知栏里的通知也一并清掉。
     * 否则一个群刷 20 条，通知栏会被它占满 —— 这也是用户抱怨「红点/消息堆」的一半来源。
     */
    private fun cancelSameConversation(sbn: StatusBarNotification) {
        try {
            cancelNotification(sbn.key)
        } catch (_: Exception) {
        }
        try {
            val title = sbn.notification?.extras
                ?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: return
            if (title.isBlank()) return
            val active = activeNotifications ?: return
            for (other in active) {
                if (other.packageName != sbn.packageName) continue
                if (other.key == sbn.key) continue
                val t = other.notification?.extras
                    ?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: continue
                if (t == title) {
                    try {
                        cancelNotification(other.key)
                    } catch (_: Exception) {
                    }
                }
            }
        } catch (_: Exception) {
        }
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
            // 高重要级 = 会响 + 从屏幕顶部浮出一张小卡片（heads-up）
            nm?.createNotificationChannel(
                NotificationChannel("nooti_alert", "Nooti 重点提醒", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "群里出现重点词时，从屏幕顶部浮出一张小卡片"
                    enableVibration(true)
                }
            )
        }
    }

    /**
     * 重点提醒卡片：从屏幕顶部浮出的一张小卡，几秒后自动收起，也可以手动叉掉。
     * 卡片上两个按钮：忽略（叉掉）/ 收入待办（存进 App）。
     *
     * 默认是「小卡片」而不是全屏盖脸 —— 全屏只在用户在设置里主动开时才用。
     */
    private fun postCard(
        title: String, text: String, pkg: String, kw: String, fullscreen: Boolean
    ) {
        try {
            ensureChannels()
            val nid = (System.currentTimeMillis() % 1000000).toInt()
            val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

            // 点卡片本身 = 打开 Nooti
            val openPi = PendingIntent.getActivity(
                this, nid + 1,
                Intent(this, MainActivity::class.java)
                    .putExtra("from_alert", true),
                flags
            )
            // 「忽略」= 叉掉，什么都不留
            val dismissPi = PendingIntent.getBroadcast(
                this, nid + 2,
                TodoReceiver.intent(this, TodoReceiver.ACTION_DISMISS, nid),
                flags
            )
            // 「收入待办」= 存进待办池
            val todoPi = PendingIntent.getBroadcast(
                this, nid + 3,
                TodoReceiver.intent(this, TodoReceiver.ACTION_TODO, nid)
                    .putExtra(TodoReceiver.EXTRA_TITLE, title)
                    .putExtra(TodoReceiver.EXTRA_TEXT, text)
                    .putExtra(TodoReceiver.EXTRA_PKG, pkg)
                    .putExtra(TodoReceiver.EXTRA_KW, kw),
                flags
            )

            val head = if (kw.isNotBlank()) "命中「$kw」· $title" else "重要消息 · $title"
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, "nooti_alert")
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
            }
            builder
                .setContentTitle(head)
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentIntent(openPi)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_MESSAGE)
                .addAction(action(android.R.drawable.ic_menu_close_clear_cancel, "忽略", dismissPi))
                .addAction(action(android.R.drawable.ic_input_add, "收入待办", todoPi))

            // 全屏强提醒是可选的：默认只浮小卡片，不盖住你正在做的事
            if (fullscreen) {
                builder
                    .setCategory(Notification.CATEGORY_ALARM)
                    .setFullScreenIntent(openPi, true)
            }

            val nm = getSystemService(NotificationManager::class.java)
            nm?.notify(nid, builder.build())
        } catch (_: Exception) {
        }
    }

    /** 卡片上的按钮（老系统没有 Action.Builder，退回老构造器） */
    private fun action(icon: Int, label: String, pi: PendingIntent): Notification.Action {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Notification.Action.Builder(icon, label, pi).build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Action(icon, label, pi)
        }
    }
}
