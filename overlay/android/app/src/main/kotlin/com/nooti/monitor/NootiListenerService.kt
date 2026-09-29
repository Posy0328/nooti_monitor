package com.nooti.monitor

import android.app.Notification
import android.app.NotificationManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * 通知监听服务：App 拿到「通知使用权」后，系统每弹出一条通知
 * （微信里设了「消息免打扰」的群也一样——那只是不响，通知仍会进通知栏），
 * 这里都会被调用一次。我们读出 标题 / 内容 / 时间 / 是否静默，存进 CapturedStore，
 * 界面每秒来取一次展示。
 */
class NootiListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val n = sbn.notification ?: return
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        // 免打扰/静默：通知渠道的重要级别低于等于 LOW，说明它不响不弹（正是免打扰群）
        var silent = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val nm = getSystemService(NotificationManager::class.java)
                val ch = nm?.getNotificationChannel(n.channelId)
                if (ch != null && ch.importance <= NotificationManager.IMPORTANCE_LOW) silent = true
            } catch (_: Exception) {
            }
        }

        val item = HashMap<String, Any>()
        item["pkg"] = sbn.packageName ?: ""
        item["title"] = title
        item["text"] = text
        item["time"] = sbn.postTime
        item["silent"] = silent
        CapturedStore.add(item)
    }
}
