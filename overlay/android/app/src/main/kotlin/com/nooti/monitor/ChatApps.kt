package com.nooti.monitor

/**
 * 聊天应用白名单：默认只盯着这些 App 的通知。
 *
 * 为什么需要它：像代理工具的网速统计、输入法、系统更新这类通知每秒都在刷，
 * 全收进来一天能灌满几百条，把真正的微信/QQ 消息淹掉（真机实测 500 条全是杂讯、
 * 一条微信都没有）。所以默认只收聊天应用，其他的看都不看；
 * 测试想收全量时，把规则里的 watchOthers 打开即可。
 */
object ChatApps {

    val ALL: Set<String> = setOf(
        "com.tencent.mm",          // 微信
        "com.tencent.mobileqq",    // QQ
        "com.tencent.tim",         // TIM
        "com.tencent.qqlite",      // QQ 轻聊版
        "com.tencent.mobileqqi",   // QQ 国际版
        "com.tencent.wework",      // 企业微信
        "com.alibaba.android.rimet", // 钉钉
        "com.ss.android.lark",     // 飞书
        "com.whatsapp",            // WhatsApp
        "org.telegram.messenger",  // Telegram
    )

    fun isChat(pkg: String?): Boolean = pkg != null && ALL.contains(pkg)

    /** 给人看的名字（界面显示用） */
    fun nameOf(pkg: String?): String = when (pkg) {
        "com.tencent.mm" -> "微信"
        "com.tencent.mobileqq" -> "QQ"
        "com.tencent.tim" -> "TIM"
        "com.tencent.wework" -> "企业微信"
        "com.alibaba.android.rimet" -> "钉钉"
        "com.ss.android.lark" -> "飞书"
        "com.whatsapp" -> "WhatsApp"
        "org.telegram.messenger" -> "Telegram"
        else -> pkg ?: ""
    }
}
