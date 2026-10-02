package com.nooti.monitor

import android.app.Activity
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager

/**
 * 锁屏兜底用的提醒页。
 *
 * 正常情况（屏幕亮着、有悬浮窗权限）走 OverlayAlert，卡片直接浮在屏幕中央。
 * 但锁屏 / 息屏时系统不允许 App 往屏幕上贴悬浮窗，这时用「全屏意图」把本页拉起来——
 * 锁屏状态下系统**会**给全屏，所以这条路过得去。
 *
 * 卡片外观完全复用 CardBuilder，保证两条通道长得一模一样。
 */
class AlertActivity : Activity() {

    private val autoCloseMs = 60_000L
    private val handler = Handler(Looper.getMainLooper())
    private var nid = 0

    companion object {
        const val EXTRA_NID = "nid"
        const val EXTRA_GROUP = "group"
        const val EXTRA_SENDER = "sender"
        const val EXTRA_BODY = "body"
        const val EXTRA_LEVEL = "level"
        const val EXTRA_PKG = "pkg"
        const val EXTRA_KW = "kw"
        const val EXTRA_TIME = "when"
        const val EXTRA_PLACE = "place"
        const val EXTRA_EVENT = "event"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 锁屏上也要能弹出来（老系统用 window flag，新系统用官方方法）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        val i = intent
        nid = i.getIntExtra(EXTRA_NID, 0)
        val data = AlertData(
            group = i.getStringExtra(EXTRA_GROUP) ?: "重要消息",
            sender = i.getStringExtra(EXTRA_SENDER) ?: "",
            body = i.getStringExtra(EXTRA_BODY) ?: "",
            level = i.getIntExtra(EXTRA_LEVEL, NotifInfo.LEVEL_IMPORTANT),
            pkg = i.getStringExtra(EXTRA_PKG) ?: "",
            kw = i.getStringExtra(EXTRA_KW) ?: "",
            whenTxt = i.getStringExtra(EXTRA_TIME) ?: "",
            place = i.getStringExtra(EXTRA_PLACE) ?: "",
            event = i.getStringExtra(EXTRA_EVENT) ?: "",
        )

        val dark = when (data.level) {
            NotifInfo.LEVEL_URGENT -> 0xDD000000.toInt()
            NotifInfo.LEVEL_IMPORTANT -> 0xB8000000.toInt()
            else -> 0x99000000.toInt()
        }

        val (root, _) = CardBuilder.buildScene(
            this, data, dark,
            { finish() },
            { finish() },
            {
                TodoStore.add(this, data.group, data.body, data.pkg, data.kw)
                finish()
            }
        )
        setContentView(root)

        // 没人管它就一直挂着也不好，一分钟自己收起来
        handler.postDelayed({ finish() }, autoCloseMs)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        // 卡片既然已经露过面了，通知栏里那条兜底通知就别再留着占地方
        if (nid != 0) {
            try {
                getSystemService(NotificationManager::class.java)?.cancel(nid)
            } catch (_: Exception) {
            }
        }
        super.onDestroy()
    }
}
