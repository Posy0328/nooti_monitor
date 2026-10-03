package com.nooti.monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.service.notification.NotificationListenerService

/**
 * 前台保活服务：挂一条常驻通知，把进程优先级抬高，让国产系统（华为/小米等）
 * 不那么容易把我们杀掉。
 *
 * 它只做两件事：
 *  1) 活着——有前台通知的进程，被「一键清理」干掉的概率低得多；
 *  2) 每 30 秒调一次 requestRebind()：授权还在但监听服务被系统解绑时，把它重新绑上。
 *
 * 注意：它不是万能的。用户如果在系统里「强行停止」了 App，或者没给自启动/电池白名单，
 * 再强的保活也活不了——所以界面上还要引导用户开那两个设置。
 */
class KeepAliveService : Service() {

    private val handler = Handler(Looper.getMainLooper())

    private val tick = object : Runnable {
        override fun run() {
            try {
                // 授权还在的话，确保监听服务处于绑定状态；已经绑着时这是无害的空操作
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    NotificationListenerService.requestRebind(
                        ComponentName(this@KeepAliveService, NootiListenerService::class.java)
                    )
                }
            } catch (_: Exception) {
            }
            handler.postDelayed(this, 30_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        startInForeground()
        handler.postDelayed(tick, 30_000L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        // 被系统杀掉后，尽量拉起来
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startInForeground() {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm?.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL, "Nooti 后台监听", NotificationManager.IMPORTANCE_MIN
                    ).apply {
                        description = "保持监听服务活着的常驻通知（不打扰，可隐藏）"
                        setShowBadge(false)
                    }
                )
            }
            val openApp = PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this).setPriority(Notification.PRIORITY_MIN)
            }
            val n = builder
                .setContentTitle("Nooti 正在监听群消息")
                .setContentText("保持后台运行中，点我打开")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentIntent(openApp)
                .setOngoing(true)
                .build()
            startForeground(ID, n)
        } catch (_: Exception) {
        }
    }

    companion object {
        private const val CHANNEL = "nooti_keepalive"
        private const val ID = 20241003

        /** 启动保活；重复调用是无害的 */
        fun start(ctx: Context) {
            try {
                val i = Intent(ctx, KeepAliveService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(i)
                } else {
                    ctx.startService(i)
                }
            } catch (_: Exception) {
            }
        }
    }
}
