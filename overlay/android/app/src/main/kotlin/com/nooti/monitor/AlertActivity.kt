package com.nooti.monitor

import android.app.Activity
import android.app.NotificationManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 重点消息卡片 —— 这就是用户要的那种「中间突然弹出来的一张卡片」。
 *
 * 为什么不沿用系统通知横幅：系统横幅的外观（高度、圆角、按钮、配色）全部由系统决定，
 * App 改不动，所以永远"很平、跟普通弹窗一样"。要做出参考图那种质感，只能自己画。
 *
 * 卡片内容结构（自上而下）：
 *   等级色带 → [等级胶囊 + 来自哪个群] → 谁说的 → 正文原文
 *   → 抽出来的 时间 / 地点 / 事件 → [知道了] [收入待办]
 *
 * 交互：点卡片外面关掉；「知道了」关掉；「收入待办」存进 App 的待办页。
 */
class AlertActivity : Activity() {

    private val autoCloseMs = 60_000L
    private val handler = Handler(Looper.getMainLooper())
    private var nid = 0

    companion object {
        const val EXTRA_NID = "nid"
        const val EXTRA_GROUP = "group"
        const val EXTRA_SENDER = "sender"
        const val EXTRA_BODY = "body"
        const val EXTRA_LEVEL = "level"
        const val EXTRA_PKG = "pkg"
        const val EXTRA_KW = "kw"
        const val EXTRA_TIME = "when"
        const val EXTRA_PLACE = "place"
        const val EXTRA_EVENT = "event"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 锁屏上也要能弹出来（老系统用 window flag，新系统用官方方法）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        val i = intent
        nid = i.getIntExtra(EXTRA_NID, 0)
        val group = i.getStringExtra(EXTRA_GROUP) ?: "重要消息"
        val sender = i.getStringExtra(EXTRA_SENDER) ?: ""
        val body = i.getStringExtra(EXTRA_BODY) ?: ""
        val level = i.getIntExtra(EXTRA_LEVEL, NotifInfo.LEVEL_IMPORTANT)
        val pkg = i.getStringExtra(EXTRA_PKG) ?: ""
        val kw = i.getStringExtra(EXTRA_KW) ?: ""
        val whenTxt = i.getStringExtra(EXTRA_TIME) ?: ""
        val place = i.getStringExtra(EXTRA_PLACE) ?: ""
        val event = i.getStringExtra(EXTRA_EVENT) ?: ""

        setContentView(buildRoot(
            group, sender, body, level, pkg, kw, whenTxt, place, event
        ))

        // 不用管它就一直挂着也不好，给一分钟自己收起来
        handler.postDelayed({ finish() }, autoCloseMs)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        // 卡片既然已经露过面了，通知栏里那条兜底通知就别再留着占地方
        if (nid != 0) {
            try {
                getSystemService(NotificationManager::class.java)?.cancel(nid)
            } catch (_: Exception) {
            }
        }
        super.onDestroy()
    }

    private fun dp(v: Float): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics
    ).toInt()

    private fun levelColor(lv: Int): Int = when (lv) {
        NotifInfo.LEVEL_URGENT -> Color.parseColor("#E5484D")   // 紧急 · 红
        NotifInfo.LEVEL_IMPORTANT -> Color.parseColor("#F2843C") // 重要 · 橙
        else -> Color.parseColor("#3D7FE0")                      // 一般 · 蓝
    }

    private fun levelSoft(lv: Int): Int = when (lv) {
        NotifInfo.LEVEL_URGENT -> Color.parseColor("#FDECEC")
        NotifInfo.LEVEL_IMPORTANT -> Color.parseColor("#FFF2E7")
        else -> Color.parseColor("#EAF1FC")
    }

    private fun round(corner: Float, color: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            cornerRadius = corner
        }

    private fun topRound(corner: Float, color: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            cornerRadii = floatArrayOf(corner, corner, corner, corner, 0f, 0f, 0f, 0f)
        }

    private fun text(
        s: String, sizeSp: Float, color: Int,
        bold: Boolean = false, lines: Int = 0
    ): TextView = TextView(this).apply {
        text = s
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        if (lines > 0) maxLines = lines
        includeFontPadding = false
    }

    private fun buildRoot(
        group: String, sender: String, body: String, level: Int,
        pkg: String, kw: String, whenTxt: String, place: String, event: String
    ): View {
        val accent = levelColor(level)

        // 外层：半透明黑底，点空白处关掉卡片
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#8A000000"))
            setOnClickListener { finish() }
        }

        // 卡片本体：白底大圆角
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = round(dp(22f).toFloat(), Color.WHITE)
        }

        // 顶部等级色带
        card.addView(View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(6f)
            )
            background = topRound(dp(22f).toFloat(), accent)
        })

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20f), dp(16f), dp(20f), dp(18f))
        }
        card.addView(content, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        // ① 等级胶囊 + 来源
        val head = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        head.addView(TextView(this).apply {
            text = NotifInfo.levelName(level)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(dp(9f), dp(3f), dp(9f), dp(3f))
            background = round(dp(999f).toFloat(), accent)
            includeFontPadding = false
        })
        head.addView(text(
            if (group.isBlank()) "来自 ${appName(pkg)}" else "来自 ${appName(pkg)} · $group",
            12.5f, Color.parseColor("#6B7280"), bold = false, lines = 1
        ).apply {
            setPadding(dp(8f), 0, 0, 0)
            ellipsize = android.text.TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        content.addView(head)

        // ② 谁说的
        if (sender.isNotBlank()) {
            content.addView(text("${sender.trim()} 说", 13f, Color.parseColor("#8A93A5"))
                .apply { setPadding(0, dp(12f), 0, 0) })
        }

        // ③ 正文
        content.addView(text(body, 17f, Color.parseColor("#1C2330"), lines = 8)
            .apply { setPadding(0, if (sender.isBlank()) dp(12f) else dp(6f), 0, 0) })

        // ④ 抽出来的线索（有才显示）
        val facts = ArrayList<Pair<String, String>>()
        if (whenTxt.isNotBlank()) facts.add("时间" to whenTxt)
        if (place.isNotBlank()) facts.add("地点" to place)
        if (event.isNotBlank()) facts.add("事件" to event)
        if (kw.isNotBlank()) facts.add("命中" to "「$kw」")
        if (facts.isNotEmpty()) {
            val box = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                background = round(dp(12f).toFloat(), Color.parseColor("#F4F6FA"))
                setPadding(dp(12f), dp(10f), dp(12f), dp(10f))
            }
            for ((k, v) in facts) {
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                row.addView(TextView(this).apply {
                    text = k
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                    setTextColor(Color.WHITE)
                    setTypeface(typeface, Typeface.BOLD)
                    setPadding(dp(6f), dp(2f), dp(6f), dp(2f))
                    background = round(dp(6f).toFloat(), accent)
                    includeFontPadding = false
                })
                row.addView(text(v, 13f, Color.parseColor("#1C2330"), bold = true)
                    .apply { setPadding(dp(8f), 0, 0, 0) })
                box.addView(row, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { bottomMargin = dp(6f) })
            }
            content.addView(box, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(14f) })
        }

        // ⑤ 两个按钮
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val btnDismiss = TextView(this).apply {
            text = "知道了"
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14.5f)
            setTextColor(Color.parseColor("#4A5568"))
            setTypeface(typeface, Typeface.BOLD)
            background = round(dp(999f).toFloat(), Color.parseColor("#EEF1F6"))
            setOnClickListener { finish() }
        }
        val btnTodo = TextView(this).apply {
            text = "收入待办"
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14.5f)
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            background = round(dp(999f).toFloat(), accent)
            setOnClickListener {
                TodoStore.add(this@AlertActivity, group, body, pkg, kw)
                finish()
            }
        }
        actions.addView(btnDismiss, LinearLayout.LayoutParams(0, dp(46f), 1f))
        actions.addView(btnTodo, LinearLayout.LayoutParams(0, dp(46f), 1.5f).apply {
            leftMargin = dp(10f)
        })
        content.addView(actions, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(18f) })

        // 卡片放到屏幕中间偏上一点，视觉上比正中更舒服
        val cardWrap = FrameLayout(this).apply {
            setPadding(dp(22f), dp(22f), dp(22f), dp(22f))
        }
        cardWrap.addView(card, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        ))
        // 卡片自己吃掉点击（点卡片不会关），卡片以外的空白穿透到 root 上关掉卡片
        card.isClickable = true
        root.addView(cardWrap, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
        ))

        // 弹出动画：淡入 + 轻微上浮
        root.alpha = 0f
        cardWrap.translationY = dp(24f).toFloat()
        root.animate().alpha(1f).setDuration(160).start()
        cardWrap.animate().translationY(0f).setDuration(200).start()

        return root
    }

    private fun appName(pkg: String): String = when (pkg) {
        "com.tencent.mm" -> "微信"
        "com.tencent.mobileqq" -> "QQ"
        "com.alibaba.android.rimet" -> "钉钉"
        "com.tencent.wework" -> "企业微信"
        else -> "通知"
    }
}
