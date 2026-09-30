package com.nooti.monitor

/**
 * 把一条通知翻译成「卡片上要写的东西」。
 *
 * 这一步不联网、不调 AI，全用本地规则，好处是瞬间出结果、不耗电、不泄露聊天内容。
 *
 * 产出四件事：
 *   1) 等级 level —— 0 一般 / 1 重要 / 2 紧急（决定卡片配色，跟 App 里的分类体系统一）
 *   2) 来源 group + 发言人 sender —— 谁在哪说的
 *   3) 抽取 time / place / event —— 时间、地点、事件，能从正文里挖出来就挖
 *   4) 判定 kind —— 是群消息还是私聊（用「发送者: 内容」格式 + 学习记忆双重判断）
 */
object NotifInfo {

    /** 紧急词：会立刻影响你的（红色卡片） */
    private val URGENT = listOf(
        "@全体成员", "@所有人", "有人@我", "全体成员", "紧急", "加急", "马上", "立刻",
        "尽快", "速回", "速看", "今天截止", "截止今天", "最后一天", "抓紧", "改期", "取消",
    )

    /** 重要词：要处理但没那么急的（橙色卡片） */
    private val IMPORTANT = listOf(
        "截止", "交作业", "作业", "提交", "考试", "签到", "报名", "缴费", "点名", "催",
        "换教室", "停课", "调课", "统计", "填表", "材料", "成绩", "开会", "签到表", "接龙",
    )

    /** 正文里出现这些，说明事情就在眼前，等级往上提一档 */
    private val SOON = listOf(
        "今天", "今晚", "今早", "马上", "立刻", "一小时后", "半小时", "几点前", "待会儿",
        "稍后", "现在", "尽快",
    )

    /** 地点线索词 */
    private val PLACE_HINT = listOf(
        "教室", "楼", "馆", "厅", "室", "食堂", "宿舍", "操场", "会议室", "图书馆",
        "门口", "南苑", "北苑", "东区", "西区", "东门", "西门", "南门", "北门", "广场",
    )

    /** 事件归类 */
    private val EVENTS = listOf(
        "交作业" to "交作业", "作业" to "交作业",
        "考试" to "考试", "补考" to "考试", "测验" to "考试",
        "集合" to "集合", "点名" to "集合",
        "开会" to "开会", "会议" to "开会",
        "报名" to "报名", "接龙" to "报名",
        "签到" to "签到", "打卡" to "签到",
        "缴费" to "缴费", "交费" to "缴费", "收费" to "缴费",
        "面试" to "面试",
        "活动" to "活动", "讲座" to "活动", "比赛" to "活动", "晚会" to "活动",
        "填表" to "填表", "统计" to "填表", "问卷" to "填表",
        "搬" to "搬东西", "领取" to "领取", "交材料" to "交材料", "材料" to "交材料",
    )

    val LEVEL_GENERAL = 0
    val LEVEL_IMPORTANT = 1
    val LEVEL_URGENT = 2

    /** 群消息格式：开头是「某人: 内容」或者「某人：内容」。图片/表情消息也会带前缀。 */
    private val GROUP_FORMAT = Regex("^[^\\s:：]{1,16}[:：]\\s*\\S")

    /** 认一条消息是不是群消息 */
    fun looksLikeGroup(text: String): Boolean = GROUP_FORMAT.containsMatchIn(text)

    /**
     * 把「发送者: 内容」拆开。不是这个格式就返回 null。
     * 只认第一个冒号，防止内容里的冒号把句子切碎。
     */
    fun splitSender(text: String): Pair<String, String>? {
        val m = Regex("^([^\\s:：]{1,16})[:：]\\s*([\\s\\S]+)").find(text) ?: return null
        val sender = m.groupValues[1]
        val body = m.groupValues[2]
        if (body.isBlank()) return null
        return sender to body
    }

    /**
     * 定等级。
     * 优先看命中的词属于哪一档；用户自己给词标过等级的话以用户的为准。
     * 再看正文里有没有「今天/马上」这类紧迫词，有就提一档。
     */
    fun levelOf(full: String, hitWord: String, userLevels: Map<String, Int>): Int {
        var lv = when {
            userLevels.containsKey(hitWord) -> userLevels[hitWord] ?: LEVEL_IMPORTANT
            URGENT.any { hitWord.contains(it, true) } -> LEVEL_URGENT
            IMPORTANT.any { hitWord.contains(it, true) } -> LEVEL_IMPORTANT
            else -> LEVEL_IMPORTANT
        }
        // 正文里有「今天/马上」这类词，说明事情就在眼前
        if (SOON.any { full.contains(it, true) } && lv < LEVEL_URGENT) lv += 1
        return lv.coerceIn(0, 2)
    }

    /** 从正文里挖时间线索，挖不到返回空串 */
    fun pickTime(body: String): String {
        val pats = listOf(
            "(今|明|后|大后)(天|晚|早|日)(上午|下午|中午|晚上|早上|凌晨)?",
            "周[一二三四五六日天](上午|下午|中午|晚上|早上|凌晨)?",
            "星期[一二三四五六日天](上午|下午|中午|晚上|早上|凌晨)?",
            "(下|本|这)周[一二三四五六日天]?",
            "\\d{1,2}\\s*月\\s*\\d{1,2}\\s*[日号]",
            "(上午|下午|中午|晚上|早上|凌晨)?\\s*\\d{1,2}\\s*[:：]\\s*\\d{2}",
            "(上午|下午|中午|晚上|早上|凌晨)?\\s*\\d{1,2}\\s*点(半|\\d{1,2}分)?",
        )
        for (p in pats) {
            val m = Regex(p).find(body) ?: continue
            val t = m.value.trim()
            if (t.isNotEmpty()) return t
        }
        return ""
    }

    /** 从正文里挖地点线索 */
    fun pickPlace(body: String): String {
        // 先看「在/到/去 + XX教室/XX楼」这种最明确的写法
        val m = Regex("(?:在|到|去|地点[:：]?)\\s*([\\u4e00-\\u9fa5A-Za-z0-9]{1,6}(?:教室|楼|馆|厅|室|食堂|宿舍|操场|会议室|图书馆|门口))")
            .find(body)
        if (m != null) return m.groupValues[1]
        // 退一步：正文里直接出现线索词，取它前后拼出的小片段
        for (hint in PLACE_HINT) {
            val i = body.indexOf(hint)
            if (i < 0) continue
            val start = (i - 4).coerceAtLeast(0)
            val frag = body.substring(start, (i + hint.length).coerceAtMost(body.length))
                .trim(' ', '，', ',', '。', '：', ':', '、')
            if (frag.length in 2..10) return frag
        }
        return ""
    }

    /** 从正文里判断这件事是什么类型 */
    fun pickEvent(body: String): String {
        for ((k, v) in EVENTS) if (body.contains(k)) return v
        return ""
    }

    /** 等级 → 人话 */
    fun levelName(lv: Int): String = when (lv) {
        LEVEL_URGENT -> "紧急"
        LEVEL_IMPORTANT -> "重要"
        else -> "一般"
    }
}
