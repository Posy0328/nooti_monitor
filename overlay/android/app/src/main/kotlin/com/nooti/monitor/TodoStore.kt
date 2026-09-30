package com.nooti.monitor

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * 待办池：从提醒卡片上「收入待办」的消息就存在这里（SharedPreferences 持久化）。
 *
 * 和 CapturedStore 的区别：
 *  - CapturedStore 只是内存里的「抓包流水」，刷新就没了；
 *  - TodoStore 是用户主动留下来要处理的东西，会一直留着直到自己删掉。
 *
 * 之所以不放在内存里：收待办的动作发生在 BroadcastReceiver 里，
 * App 界面不一定活着，必须写盘才不会丢。
 */
object TodoStore {

    private const val PREF = "nooti_rules"
    private const val KEY = "todos"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    private fun read(ctx: Context): JSONArray =
        JSONArray(prefs(ctx).getString(KEY, "[]") ?: "[]")

    /** 用 commit() 而不是 apply()：收待办后进程可能立刻被回收，同步写盘才保险 */
    private fun write(ctx: Context, arr: JSONArray) {
        prefs(ctx).edit().putString(KEY, arr.toString()).commit()
    }

    @Synchronized
    fun add(ctx: Context, title: String, text: String, pkg: String, kw: String) {
        val arr = read(ctx)
        val o = JSONObject()
        o.put("id", "${System.currentTimeMillis()}_${arr.length()}")
        o.put("title", title)
        o.put("text", text)
        o.put("pkg", pkg)
        o.put("kw", kw)
        o.put("ts", System.currentTimeMillis())
        o.put("done", false)
        arr.put(o)
        while (arr.length() > 300) arr.remove(0)
        write(ctx, arr)
    }

    @Synchronized
    fun list(ctx: Context): String = read(ctx).toString()

    @Synchronized
    fun remove(ctx: Context, id: String) {
        val arr = read(ctx)
        val next = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (o.optString("id") != id) next.put(o)
        }
        write(ctx, next)
    }

    @Synchronized
    fun toggle(ctx: Context, id: String) {
        val arr = read(ctx)
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (o.optString("id") == id) o.put("done", !o.optBoolean("done", false))
        }
        write(ctx, arr)
    }

    @Synchronized
    fun clear(ctx: Context) = write(ctx, JSONArray())
}
