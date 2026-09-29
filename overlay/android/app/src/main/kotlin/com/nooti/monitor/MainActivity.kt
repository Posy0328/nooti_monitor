package com.nooti.monitor

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * App 主入口：在这里挂一条 Flutter 通道（nooti/listener），
 * 让界面能问系统「监听开了没有」「抓到了哪些通知」，并能一键跳到授权页。
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    else -> result.notImplemented()
                }
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
