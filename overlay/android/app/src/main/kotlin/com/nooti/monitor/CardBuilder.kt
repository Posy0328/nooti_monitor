package com.nooti.monitor

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/** 一张提醒卡片要展示的全部信息 */
data class AlertData(
    val group: String = "",
    val sender: String = "",
    val body: String = "",
    val level: Int = NotifInfo.LEVEL_IMPORTANT,
    val pkg: String = "",
    val kw: String = "",
    val whenTxt: String = "",
    val place: String = "",
    val event: String = "",
)

/**
 * 卡片外观的**唯一来源**。
 *
 * 两条弹出通道（OverlayAlert 悬浮窗 / AlertActivity 锁屏兜底）都调用这里，
 * 保证无论走哪条路，用户看到的卡片长得一模一样。
 * 全部用代码画，不依赖 res 资源文件（CI 里 res 会被 flutter create 覆盖）。
 */
object CardBuilder {

    fun dp(ctx: Context, v: Float): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v, ctx.resources.displayMetrics
    ).toInt()

    fun levelColor(lv: Int): Int = when (lv) {
        NotifInfo.LEVEL_URGENT -> Color.parseColor("#E5484D")    // 紧急 · 红
        NotifInfo.LEVEL_IMPORTANT -> Color.parseColor("#F2843C") // 重要 · 橙
        else -> Color.parseColor("#3D7FE0")                      // 一般 · 蓝
    }

    fun levelSoft(lv: Int): Int = when (lv) {
        NotifInfo.LEVEL_URGENT -> Color.parseColor("#FDECEC")
        NotifInfo.LEVEL_IMPORTANT -> Color.parseColor("#FFF3E9")
        else -> Color.parseColor("#EAF1FC")
    }

    /** 徽章上写什么：紧急的要一眼看出「必须现在处理」 */
    fun levelBadge(lv: Int): String = when (lv) {
        NotifInfo.LEVEL_URGENT -> "紧急 · 马上看"
        NotifInfo.LEVEL_IMPORTANT -> "重要"
        else -> "提醒"
    }

    fun appName(pkg: String): String = when (pkg) {
        "com.tencent.mm" -> "微信"
        "com.tencent.mobileqq" -> "QQ"
        "com.alibaba.android.rimet" -> "钉钉"
        "com.tencent.wework" -> "企业微信"
        else -> "通知"
    }

    fun round(corner: Float, color: Int): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(color)
        cornerRadius = corner
    }

    private fun topRound(corner: Float, color: Int): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(color)
        cornerRadii = floatArrayOf(corner, corner, corner, corner, 0f, 0f, 0f, 0f)
    }

    private fun tv(
        ctx: Context, s: String, sizeSp: Float, color: Int,
        bold: Boolean = false, lines: Int = 0
    ): TextView = TextView(ctx).apply {
        text = s
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        if (lines > 0) maxLines = lines
        includeFontPadding = false
    }

    /**
     * 造卡片本体（不含遮罩，不含容器）。
     * @param onDismiss 用户点了「知道了」
     * @param onTodo    用户点了「收入待办」
     */
    fun buildCard(
        ctx: Context, d: AlertData,
        onDismiss: () -> Unit, onTodo: () -> Unit
    ): View {
        val accent = levelColor(d.level)

        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = round(dp(ctx, 24f).toFloat(), Color.WHITE)
            // 卡片自己吃掉点击，避免点正文被当成「点空白」关掉
            isClickable = true
            elevation = dp(ctx, 18f).toFloat()
        }

        // 顶部等级色带
        card.addView(View(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(ctx, 8f)
            )
            background = topRound(dp(ctx, 24f).toFloat(), accent)
        })

        val content = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(ctx, 22f), dp(ctx, 18f), dp(ctx, 22f), dp(ctx, 20f))
        }
        card.addView(
            content,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        // ① 等级徽章 + 来源
        val head = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        head.addView(TextView(ctx).apply {
            text = levelBadge(d.level)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(dp(ctx, 10f), dp(ctx, 4f), dp(ctx, 10f), dp(ctx, 4f))
            background = round(dp(ctx, 999f).toFloat(), accent)
            includeFontPadding = false
        })
        head.addView(
            tv(
                ctx,
                if (d.group.isBlank()) "来自 ${appName(d.pkg)}"
                else "来自 ${appName(d.pkg)} · ${d.group}",
                12.5f, Color.parseColor("#6B7280"), lines = 1
            ).apply {
                setPadding(dp(ctx, 8f), 0, 0, 0)
                ellipsize = TextUtils.TruncateAt.END
            },
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        )
        content.addView(head)

        // ② 谁说的
        if (d.sender.isNotBlank()) {
            content.addView(
                tv(ctx, "${d.sender.trim()} 说", 13f, Color.parseColor("#8A93A5"))
                    .apply { setPadding(0, dp(ctx, 14f), 0, 0) }
            )
        }

        // ③ 正文原文
        content.addView(
            tv(ctx, d.body, 17.5f, Color.parseColor("#1C2330"), lines = 10)
                .apply {
                    setPadding(0, if (d.sender.isBlank()) dp(ctx, 14f) else dp(ctx, 6f), 0, 0)
                    setLineSpacing(dp(ctx, 5f).toFloat(), 1f)
                }
        )

        // ④ 抽出来的线索
        val facts = ArrayList<Pair<String, String>>()
        if (d.whenTxt.isNotBlank()) facts.add("时间" to d.whenTxt)
        if (d.place.isNotBlank()) facts.add("地点" to d.place)
        if (d.event.isNotBlank()) facts.add("事件" to d.event)
        if (d.kw.isNotBlank()) facts.add("命中" to "「${d.kw}」")
        if (facts.isNotEmpty()) {
            val box = LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                background = round(dp(ctx, 14f).toFloat(), levelSoft(d.level))
                setPadding(dp(ctx, 14f), dp(ctx, 11f), dp(ctx, 14f), dp(ctx, 11f))
            }
            for ((k, v) in facts) {
                val row = LinearLayout(ctx).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                row.addView(TextView(ctx).apply {
                    text = k
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                    setTextColor(Color.WHITE)
                    setTypeface(typeface, Typeface.BOLD)
                    setPadding(dp(ctx, 7f), dp(ctx, 2f), dp(ctx, 7f), dp(ctx, 2f))
                    background = round(dp(ctx, 6f).toFloat(), accent)
                    includeFontPadding = false
                })
                row.addView(
                    tv(ctx, v, 13.5f, Color.parseColor("#1C2330"), bold = true)
                        .apply { setPadding(dp(ctx, 9f), 0, 0, 0) }
                )
                box.addView(
                    row,
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                    ).apply { bottomMargin = dp(ctx, 6f) }
                )
            }
            content.addView(
                box,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = dp(ctx, 16f) }
            )
        }

        // ⑤ 两个按钮
        val actions = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        actions.addView(TextView(ctx).apply {
            text = "知道了"
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTextColor(Color.parseColor("#4A5568"))
            setTypeface(typeface, Typeface.BOLD)
            isClickable = true
            background = round(dp(ctx, 999f).toFloat(), Color.parseColor("#EEF1F6"))
            setOnClickListener { onDismiss() }
        }, LinearLayout.LayoutParams(0, dp(ctx, 48f), 1f))

        actions.addView(TextView(ctx).apply {
            text = "收入待办"
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
            isClickable = true
            background = round(dp(ctx, 999f).toFloat(), accent)
            setOnClickListener { onTodo() }
        }, LinearLayout.LayoutParams(0, dp(ctx, 48f), 1.45f).apply {
            leftMargin = dp(ctx, 10f)
        })

        content.addView(
            actions,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(ctx, 20f) }
        )

        return card
    }

    /**
     * 造一整个「屏幕正中央弹一张卡」的场面：深色遮罩 + 居中的卡片。
     * @param dark 遮罩浓度。越深越有「强制看」的压迫感。
     */
    fun buildScene(
        ctx: Context, d: AlertData, dark: Int,
        onOutside: () -> Unit, onDismiss: () -> Unit, onTodo: () -> Unit
    ): Pair<View, View> {
        val root = FrameLayout(ctx).apply {
            setBackgroundColor(dark)
            isClickable = true
            setOnClickListener { onOutside() }
        }
        val card = buildCard(ctx, d, onDismiss, onTodo)

        val wrap = FrameLayout(ctx).apply {
            setPadding(dp(ctx, 22f), dp(ctx, 22f), dp(ctx, 22f), dp(ctx, 22f))
            isClickable = true
        }
        wrap.addView(
            card,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        )
        root.addView(
            wrap,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        return root to wrap
    }
}
