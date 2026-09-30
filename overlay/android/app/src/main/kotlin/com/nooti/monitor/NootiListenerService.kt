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
 * v6 核心变化：
 *  1) 命中重点词不再发系统横幅，而是弹出 App 自己画的卡片（AlertActivity）——
 *     外观、等级配色、按钮全由我们控制，才能做出「一眼看出轻重」的效果。
 *  2) 新增「所有群都安静」开关：不用一个个加群名，靠「发送者: 内容」格式 + 自动学到的群名单判断。
 *  3) 自动学习群名单：某个会话只要出现过群格式的消息，就记成「它是群」，下次不用再猜。
 *  4) 每条通知都记下「判定原因」，界面里的诊断列表能直接看到为什么静音 / 为什么没静音。
 */
class NootiListenerService : NotificationListenerService() {

    // 同一个群 8 秒内只弹一张卡片，防止刷屏
    private val lastAlertAt = HashMap<String, Long>()

    override fun onCreate() {
        super.onCreate()
        ensureChannels()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val n = sbn.notification ?: return
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        val pkgName = sbn.packageName ?: ""
        var isGroup = NotifInfo.looksLikeGroup(text)
        // 自动学习：出现过群格式的会话，永久记为群；下次连图片消息也能认出来
        if (isGroup && title.isNotBlank()) GroupStore.mark(this, pkgName, title, true)
        if (!isGroup && title.isNotBlank()) isGroup = GroupStore.isGroup(this, pkgName, title)
        recordDiscovered(pkgName, title, text, isGroup)

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

        var muted = false
        var alerted = false
        var hitWord = ""
        var reason = "不过滤（没开总开关）"

        try {
            val prefs = getSharedPreferences("nooti_rules", Context.MODE_PRIVATE)
            val raw = prefs.getString("rules", "") ?: ""
            if (raw.isNotEmpty()) {
                val rules = JSONObject(raw)
                val enabled = rules.optBoolean("enabled", false)
                val allGroups = rules.optBoolean("allGroups", false)

                if (!enabled) {
                    reason = "过滤总开关关着"
                } else if (sbn.packageName == packageName) {
                    reason = "Nooti 自己的通知"
                } else {
                    // 这个会话要不要安静：名字在名单里，或者「所有群都安静」模式下认出来的群
                    var named = false
                    val groups = rules.optJSONArray("groups")
                    if (groups != null) {
                        for (i in 0 until groups.length()) {
                            val g = groups.optString(i, "")
                            if (g.isNotBlank() &&
                                (title.contains(g, true) || text.contains(g, true))
                            ) {
                                named = true
                                break
                            }
                        }
                    }
                    val quiet = named || (allGroups && isGroup)

                    // 命中重点词
                    val keywords = rules.optJSONArray("keywords")
                    if (keywords != null) {
                        val full = "$title $text"
                        for (i in 0 until keywords.length()) {
                            val k = keywords.optString(i, "")
                            if (k.isNotBlank() && full.contains(k, true)) {
                                hitWord = k
                                break
                            }
                        }
                    }

                    // 私聊保护：明显是私聊的（没群格式、也没学过它是群），就算名字误进了名单也不吞
                    val swallowable = isGroup || named

                    if (quiet && hitWord.isNotEmpty() && swallowable) {
                        muted = true
                        val level = NotifInfo.levelOf("$title $text", hitWord, levelsFrom(rules))
                        val minLevel = rules.optInt("minLevel", 0)
                        cancelSameConversation(sbn)
                        if (level >= minLevel) {
                            alerted = true
                            reason = "命中「$hitWord」· ${NotifInfo.levelName(level)}，弹卡片"
                            popCard(title, text, pkgName, hitWord, rules, isGroup, level)
                        } else {
                            reason = "命中「$hitWord」但等级不够（${NotifInfo.levelName(level)}），只安静收录"
                        }
                    } else if (quiet && swallowable) {
                        muted = true
                        reason = if (named) "在安静名单里，静音" else "「所有群都安静」生效，静音"
                        cancelSameConversation(sbn)
                    } else if (hitWord.isNotEmpty()) {
                        reason = "命中「$hitWord」，但这个会话没设安静"
                    } else if (quiet && !swallowable) {
                        reason = "看起来是私聊，放行（私聊保护）"
                    } else if (isGroup) {
                        reason = "是群消息，但没设安静也没命中词"
                    } else {
                        reason = "没命中任何词"
                    }
                }
            }
        } catch (e: Exception) {
            reason = "内部错误：${e.message}"
        }

        val item = HashMap<String, Any>()
        item["pkg"] = sbn.packageName ?: ""
        item["title"] = title
        item["text"] = text
        item["time"] = sbn.postTime
        item["silent"] = silent
        item["muted"] = muted
        item["alerted"] = alerted
        item["isGroup"] = isGroup
        item["reason"] = reason
        item["kw"] = hitWord
        CapturedStore.add(item)
    }

    /** 读取用户给每个关键词标过的等级 */
    private fun levelsFrom(rules: JSONObject): Map<String, Int> {
        val m = HashMap<String, Int>()
        rules.optJSONObject("kwLevel")?.let { lv ->
            for (k in lv.keys()) m[k] = lv.optInt(k, NotifInfo.LEVEL_IMPORTANT)
        }
        return m
    }

    /** 弹出我们自己画的卡片（走全屏意图；系统不允许时会降级成一条横幅兜底） */
    private fun popCard(
        group: String, rawText: String, pkg: String, kw: String,
        rules: JSONObject, isGroup: Boolean, level: Int
    ) {
        try {
            // 同群 8 秒去重，防止一分钟刷十张卡片
            val now = System.currentTimeMillis()
            if (now - (lastAlertAt[group] ?: 0L) < 8000) return
            lastAlertAt[group] = now

            ensureChannels()
            val nid = (now % 1000000).toInt()

            val pair = if (isGroup) NotifInfo.splitSender(rawText) else null
            val sender = pair?.first ?: ""
            val body = pair?.second ?: rawText

            val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            val alert = Intent(this, AlertActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra(AlertActivity.EXTRA_GROUP, group)
                putExtra(AlertActivity.EXTRA_SENDER, sender)
                putExtra(AlertActivity.EXTRA_BODY, body)
                putExtra(AlertActivity.EXTRA_LEVEL, level)
                putExtra(AlertActivity.EXTRA_PKG, pkg)
                putExtra(AlertActivity.EXTRA_KW, kw)
                putExtra(AlertActivity.EXTRA_TIME, NotifInfo.pickTime(body))
                putExtra(AlertActivity.EXTRA_PLACE, NotifInfo.pickPlace(body))
                putExtra(AlertActivity.EXTRA_EVENT, NotifInfo.pickEvent(body))
                putExtra(AlertActivity.EXTRA_NID, nid)
            }
            val pi = PendingIntent.getActivity(this, nid, alert, flags)

            // 兜底通知：系统若不让全屏，它会以横幅形式出现；卡片正常弹出时，
            // 用户在卡片上处理完，AlertActivity 会把这条通知撤掉，不留痕迹。
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, "nooti_alert")
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
            }
            builder
                .setContentTitle("${NotifInfo.levelName(level)} · $group")
                .setContentText(body)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(pi)
                .setFullScreenIntent(pi, true)
                .setCategory(Notification.CATEGORY_MESSAGE)
                .setAutoCancel(true)

            val nm = getSystemService(NotificationManager::class.java)
            nm?.notify(nid, builder.build())
        } catch (_: Exception) {
        }
    }

    /**
     * 静音一条群消息时，把同一个会话此前堆在通知栏里的通知也一并清掉。
     * 否则一个群刷 20 条，通知栏会被它占满。
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

    // 把微信/QQ里出现过消息的对话标题记下来（标题去重，最多留 80 条）
    private fun recordDiscovered(pkg: String, title: String, text: String, isGroup: Boolean) {
        if (title.isBlank()) return
        if (pkg != "com.tencent.mm" && pkg != "com.tencent.mobileqq") return
        try {
            val prefs = getSharedPreferences("nooti_rules", Context.MODE_PRIVATE)
            val arr = JSONArray(prefs.getString("discovered", "[]") ?: "[]")
            var found = false
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                if (o.optString("pkg") == pkg && o.optString("t") == title) {
                    // 顺带保留最近一条内容，界面上能看到它到底在说什么，方便判断是不是群
                    o.put("g", o.optBoolean("g", false) || isGroup)
                    o.put("last", text)
                    o.put("ts", System.currentTimeMillis())
                    found = true
                    break
                }
            }
            if (!found) {
                val o = JSONObject()
                o.put("pkg", pkg)
                o.put("t", title)
                o.put("g", isGroup)
                o.put("last", text)
                o.put("ts", System.currentTimeMillis())
                arr.put(o)
            }
            while (arr.length() > 80) arr.remove(0)
            prefs.edit().putString("discovered", arr.toString()).apply()
        } catch (_: Exception) {
        }
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            // 高重要级：全屏意图需要它；系统若拒绝全屏，它会以横幅作为兜底
            nm?.createNotificationChannel(
                NotificationChannel(
                    "nooti_alert", "Nooti 重点提醒", NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "重点消息弹出自绘卡片；系统不允许弹卡片时以横幅兜底"
                    enableVibration(true)
                }
            )
        }
    }
}
