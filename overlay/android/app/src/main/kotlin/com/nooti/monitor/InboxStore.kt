package com.nooti.monitor

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * 全部收到的消息（落盘保存，供测试期观察统计）。
 *
 * 跟 CapturedStore 的区别：
 *   CapturedStore 是「最近 60 条的诊断流水」，只在内存里，重启就清空；
 *   InboxStore 会把**每一条通知都收下**——不管它重不重要、有没有弹卡片、有没有进待办。
 *   这样测试期不用一直盯着屏幕，回头打开 App 就能看到「一共收到多少、都是些什么」。
 */
object InboxStore {

    private const val PREFS = "nooti_inbox"
    private const val KEY = "items"
    private const val MAX = 500

    fun add(ctx: Context, item: Map<String, Any>) {
        try {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = JSONArray(prefs.getString(KEY, "[]") ?: "[]")
            val o = JSONObject()
            for ((k, v) in item) o.put(k, v)

            // 同一个会话的连续同内容：只更新时间，不重复堆条数（避免刷屏把列表冲爆）
            if (arr.length() > 0) {
                val last = arr.optJSONObject(arr.length() - 1)
                if (last != null &&
                    last.optString("title") == o.optString("title") &&
                    last.optString("text") == o.optString("text") &&
                    last.optString("pkg") == o.optString("pkg")
                ) {
                    last.put("time", o.optLong("time"))
                    last.put("count", last.optInt("count", 1) + 1)
                    prefs.edit().putString(KEY, arr.toString()).commit()
                    return
                }
            }

            o.put("count", 1)
            arr.put(o)
            while (arr.length() > MAX) arr.remove(0)
            prefs.edit().putString(KEY, arr.toString()).commit()
        } catch (_: Exception) {
        }
    }

    fun list(ctx: Context): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        try {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = JSONArray(prefs.getString(KEY, "[]") ?: "[]")
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val m = HashMap<String, Any>()
                for (k in o.keys()) m[k] = o.get(k)
                out.add(m)
            }
        } catch (_: Exception) {
        }
        return out.reversed()   // 新的在前
    }

    fun clear(ctx: Context) {
        try {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY, "[]").commit()
        } catch (_: Exception) {
        }
    }
}
