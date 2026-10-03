package com.nooti.monitor

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * App 主入口：挂 Flutter 通道（nooti/listener）。
 * 提供：监听状态 / 跳授权页 / 抓包数据 / 过滤规则 / 发现的群组 /
 * 通知权限与全屏提醒权限的查询和申请。
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureChannels()
        // 用户打开 App 时顺手把保活服务拉起来——它活着，监听才不容易被系统杀掉
        KeepAliveService.start(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nooti/listener")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(isListenerEnabled())
                    // 监听服务的心跳：授权在但长时间没心跳 = 服务被系统杀了/解绑了
                    "listenerAlive" -> {
                        val ts = getSharedPreferences("nooti_rules", MODE_PRIVATE)
                            .getLong("listener_ts", 0L)
                        result.success(ts)
                    }
                    "requestRebind" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                android.service.notification.NotificationListenerService
                                    .requestRebind(
                                        ComponentName(this, NootiListenerService::class.java)
                                    )
                            }
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    // 电池优化白名单：不在名单里的话，国产系统随时可能把我们冻结
                    "batteryOk" -> result.success(
                        (getSystemService(PowerManager::class.java))
                            .isIgnoringBatteryOptimizations(packageName)
                    )
                    "openBatterySettings" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        } catch (_: Exception) {
                            try {
                                startActivity(
                                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                )
                            } catch (_: Exception) {
                            }
                        }
                        result.success(true)
                    }
                    // 自启动管理：各厂商入口不一样，挨个试，都不行就退到应用详情页
                    "openAutoStartSettings" -> {
                        val tries = listOf(
                            Intent().setComponent(
                                ComponentName(
                                    "com.huawei.systemmanager",
                                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                                )
                            ),
                            Intent().setComponent(
                                ComponentName(
                                    "com.huawei.systemmanager",
                                    "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity"
                                )
                            ),
                            Intent().setComponent(
                                ComponentName(
                                    "com.miui.securitycenter",
                                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                                )
                            ),
                            Intent().setComponent(
                                ComponentName(
                                    "com.coloros.safecenter",
                                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                                )
                            ),
                        )
                        var opened = false
                        for (i in tries) {
                            try {
                                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(i)
                                opened = true
                                break
                            } catch (_: Exception) {
                            }
                        }
                        if (!opened) {
                            try {
                                startActivity(
                                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                        .setData(Uri.parse("package:$packageName"))
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                            } catch (_: Exception) {
                            }
                        }
                        result.success(true)
                    }
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
                    "getDiscovered" -> result.success(
                        getSharedPreferences("nooti_rules", MODE_PRIVATE)
                            .getString("discovered", "[]") ?: "[]"
                    )
                    "getLearned" -> result.success(GroupStore.list(this))
                    "markAsGroup" -> {
                        GroupStore.mark(
                            this,
                            call.argument<String>("pkg") ?: "com.tencent.mm",
                            call.argument<String>("t") ?: "",
                            call.argument<Boolean>("g") ?: true,
                        )
                        result.success(true)
                    }
                    "getTodos" -> result.success(TodoStore.list(this))
                    // 全量收录：测试期用来统计收到了多少消息
                    "getInbox" -> result.success(InboxStore.list(this))
                    "clearInbox" -> {
                        InboxStore.clear(this)
                        result.success(true)
                    }
                    // 悬浮窗权限：卡片要霸道地盖在屏幕中央，就靠它
                    "canOverlay" -> result.success(OverlayAlert.canShow(this))
                    "openOverlaySettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            }
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    "hideOverlay" -> {
                        OverlayAlert.dismissAll(this)
                        result.success(true)
                    }
                    "addTodo" -> {
                        TodoStore.add(
                            this,
                            call.argument<String>("title") ?: "",
                            call.argument<String>("text") ?: "",
                            call.argument<String>("pkg") ?: "",
                            call.argument<String>("kw") ?: "",
                        )
                        result.success(true)
                    }
                    "removeTodo" -> {
                        TodoStore.remove(this, call.argument<String>("id") ?: "")
                        result.success(true)
                    }
                    "toggleTodo" -> {
                        TodoStore.toggle(this, call.argument<String>("id") ?: "")
                        result.success(true)
                    }
                    "clearTodos" -> {
                        TodoStore.clear(this)
                        result.success(true)
                    }
                    "openNotifySettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            )
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
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
                    "canFullScreen" -> result.success(
                        if (Build.VERSION.SDK_INT >= 34) {
                            (getSystemService(NotificationManager::class.java))
                                .canUseFullScreenIntent()
                        } else true
                    )
                    "openFullScreenSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= 34) {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            } else {
                                startActivity(
                                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                )
                            }
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // 建「重点提醒」通道（高重要级=会响 + 从顶部浮出小卡片）；重复创建是无害的空操作
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
