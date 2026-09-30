package com.nooti.monitor

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/**
 * 处理提醒卡片上的两个按钮。
 *
 * 卡片上只有两个动作，刻意做少：
 *   收入待办 —— 这条消息存进 App 的待办池，通知消失；
 *   忽略     —— 等于叉掉，通知消失，什么都不留。
 *
 * 用广播而不是跳页面：点按钮不该把微信/你当前在用的 App 顶掉。
 */
class TodoReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_TODO = "com.nooti.monitor.TODO"
        const val ACTION_DISMISS = "com.nooti.monitor.DISMISS"
        const val EXTRA_NID = "nid"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PKG = "pkg"
        const val EXTRA_KW = "kw"

        fun intent(ctx: Context, action: String, nid: Int): Intent =
            Intent(action)
                .setComponent(ComponentName(ctx, TodoReceiver::class.java))
                .putExtra(EXTRA_NID, nid)
    }

    override fun onReceive(ctx: Context, intent: Intent) {
        val nid = intent.getIntExtra(EXTRA_NID, 0)

        if (intent.action == ACTION_TODO) {
            TodoStore.add(
                ctx,
                intent.getStringExtra(EXTRA_TITLE) ?: "",
                intent.getStringExtra(EXTRA_TEXT) ?: "",
                intent.getStringExtra(EXTRA_PKG) ?: "",
                intent.getStringExtra(EXTRA_KW) ?: ""
            )
        }

        // 不管点哪个按钮，这张卡片都该立刻消失
        try {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            nm?.cancel(nid)
        } catch (_: Exception) {
        }
    }
}
