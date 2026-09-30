package com.nooti.monitor

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * 群名单记忆：记住哪些会话是「群」，哪些是「个人」。
 *
 * 为什么要记：系统给的通知里只有一个标题，没有「这是群还是私聊」的标记。
 * 只能从正文格式（「某人: 内容」）去猜，而图片、表情类消息猜不出来。
 * 所以一旦某会话出现过群格式消息，就永久记下来；用户也能在界面里手动纠正。
 *
 * 这份名单同时喂给两处：① 判断要不要静音；② 界面上「发现列表」里显示群/个人标签。
 */
object GroupStore {

    private const val PREF = "nooti_rules"
    private const val KEY = "learned"
    private const val MAX = 150

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    private fun read(ctx: Context): JSONArray =
        JSONArray(prefs(ctx).getString(KEY, "[]") ?: "[]")

    private fun write(ctx: Context, arr: JSONArray) {
        prefs(ctx).edit().putString(KEY, arr.toString()).apply()
    }

    /** 给界面读的 JSON 字符串 */
    fun list(ctx: Context): String = read(ctx).toString()

    /**
     * 标记 / 取消标记一个会话是群。
     * isGroup = true 记进名单；false 则把它从名单里剔除（用户说它不是群）。
     */
    @Synchronized
    fun mark(ctx: Context, pkg: String, title: String, isGroup: Boolean) {
        if (title.isBlank()) return
        val arr = read(ctx)
        val next = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (o.optString("pkg") == pkg && o.optString("t") == title) continue
            next.put(o)
        }
        if (isGroup) {
            val o = JSONObject()
            o.put("pkg", pkg)
            o.put("t", title)
            o.put("ts", System.currentTimeMillis())
            next.put(o)
        }
        while (next.length() > MAX) next.remove(0)
        write(ctx, next)
    }

    @Synchronized
    fun isGroup(ctx: Context, pkg: String, title: String): Boolean {
        if (title.isBlank()) return false
        return try {
            val arr = read(ctx)
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                if (o.optString("pkg") == pkg && o.optString("t") == title) return true
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    /** 所有记过的群名（不带包名），供界面做「这个群名我认识」判断 */
    fun titles(ctx: Context): List<String> {
        val out = ArrayList<String>()
        try {
            val arr = read(ctx)
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.optString("t")?.takeIf { it.isNotBlank() }?.let { out.add(it) }
            }
        } catch (_: Exception) {
        }
        return out
    }
}
