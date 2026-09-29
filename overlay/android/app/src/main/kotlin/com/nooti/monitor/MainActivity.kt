package com.nooti.monitor

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * App 主入口：挂 Flutter 通道（nooti/listener）。
 * 提供：监听状态查询 / 跳授权页 / 抓包数据读写 / 过滤规则读写 /
 * 通知权限（重点提醒用）查询与申请。
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureChannels()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nooti/listener")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(isListenerEnabled())
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(true)
                    }
                    "getCaptured" -> result.success(CapturedStore.snapshot())
                    "clear" -> {
                        CapturedStore.clear()
                        result.success(true)
                    }
                    "setRules" -> {
                        val json = call.argument<String>("json") ?: "{}"
                        getSharedPreferences("nooti_rules", MODE_PRIVATE)
                            .edit().putString("rules", json).apply()
                        result.success(true)
                    }
                    "getRules" -> result.success(
                        getSharedPreferences("nooti_rules", MODE_PRIVATE)
                            .getString("rules", "") ?: ""
                    )
                    "canNotify" -> result.success(
                        (getSystemService(NotificationManager::class.java))
                            .areNotificationsEnabled()
                    )
                    "requestNotifyPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1
                            )
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // 建「重点提醒」通道（高重要级=会响会弹）；重复创建是无害的空操作
    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(
                NotificationChannel("nooti_alert", "Nooti 重点提醒", NotificationManager.IMPORTANCE_HIGH)
            )
        }
    }

    // 读系统安全设置里的「已启用通知监听的应用」名单，看有没有包含本应用
    private fun isListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        ) ?: return false
        return flat.split(":").any { it.startsWith(packageName) }
    }
}
