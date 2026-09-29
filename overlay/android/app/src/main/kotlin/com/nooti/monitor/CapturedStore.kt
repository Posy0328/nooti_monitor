package com.nooti.monitor

/** 内存里暂存抓到的通知（最新的在前面），供界面每秒拉取一次展示 */
object CapturedStore {
    private val items = ArrayList<Map<String, Any>>()

    @Synchronized
    fun add(m: Map<String, Any>) {
        items.add(0, m)
        if (items.size > 200) items.removeAt(items.size - 1)
    }

    @Synchronized
    fun snapshot(): List<Map<String, Any>> = ArrayList(items)

    @Synchronized
    fun clear() = items.clear()
}
