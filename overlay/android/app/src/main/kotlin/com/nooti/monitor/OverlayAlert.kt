package com.nooti.monitor

import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import java.util.ArrayDeque

/**
 * 悬浮窗版提醒卡片 —— 这是「霸道地出现在屏幕正中央」的唯一实现方式。
 *
 * 为什么不能继续用系统通知：
 *   安卓 10 之后，只要手机屏幕是亮的，系统就会把「全屏意图」降级成顶部一条窄横幅；
 *   它长得跟普通消息一模一样、几秒就溜走、还必须点一下才展开。用户要的「强制看见」做不到。
 *
 * 悬浮窗（申请「显示在其他应用上层」权限后）不受这条规则限制：
 * 可以盖在任意 App、任意界面上，卡片直接就在屏幕中间，不需要用户点任何东西。
 */
object OverlayAlert {

    private var wm: WindowManager? = null
    private var current: View? = null
    private var autoClose: Runnable? = null
    private val handler = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<Pair<AlertData, Long>>()

    /** 有没有拿到「显示在其他应用上层」权限 */
    fun canShow(ctx: Context): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(ctx) else true
    } catch (_: Exception) {
        false
    }

    /**
     * 弹一张卡片。返回 true = 真的弹出来了；false = 没权限，调用方需要走别的兜底。
     * 屏幕上已经有一张时，这张先排队，等前面那张收了自动接上。
     */
    fun show(ctx: Context, data: AlertData, autoCloseMs: Long): Boolean {
        if (!canShow(ctx)) return false
        try {
            val app = ctx.applicationContext
            handler.post { present(app, data, autoCloseMs) }
            return true
        } catch (_: Exception) {
            return false
        }
    }

    /** 屏幕上还挂着卡片吗 */
    fun isShowing(): Boolean = current != null

    /** 立刻收掉当前卡片（用户回到 App 里操作时用，避免卡片压在 App 上面） */
    fun dismissAll(ctx: Context) {
        handler.post {
            queue.clear()
            close(ctx.applicationContext)
        }
    }

    private fun present(ctx: Context, data: AlertData, autoCloseMs: Long) {
        if (current != null) {
            if (queue.size < 5) queue.addLast(data to autoCloseMs)
            return
        }
        try {
            val manager = wm ?: run {
                val m = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                wm = m
                m
            }

            // 遮罩浓度：越紧急压得越暗，「强制看」的压迫感越强
            val dark = when (data.level) {
                NotifInfo.LEVEL_URGENT -> 0xDD000000.toInt()
                NotifInfo.LEVEL_IMPORTANT -> 0xB8000000.toInt()
                else -> 0x99000000.toInt()
            }

            val (root, wrap) = CardBuilder.buildScene(
                ctx, data, dark,
                { close(ctx) },                       // 点卡片外的空白
                { close(ctx) },                       // 知道了
                {                                     // 收入待办
                    TodoStore.add(ctx, data.group, data.body, data.pkg, data.kw)
                    close(ctx)
                }
            )

            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            }

            manager.addView(root, lp)
            current = root

            // 出场：淡入 + 轻轻上浮
            root.alpha = 0f
            wrap.translationY = CardBuilder.dp(ctx, 28f).toFloat()
            root.animate().alpha(1f).setDuration(160).start()
            wrap.animate().translationY(0f).setDuration(230).start()

            val auto = Runnable { close(ctx) }
            autoClose = auto
            handler.postDelayed(auto, autoCloseMs)
        } catch (_: Exception) {
            // 弹不出来就当没发生；调用方会走兜底路径
        }
    }

    private fun close(ctx: Context) {
        val v = current ?: return
        current = null
        autoClose?.let { handler.removeCallbacks(it) }
        autoClose = null
        try {
            v.animate().alpha(0f).setDuration(130).withEndAction {
                try {
                    wm?.removeView(v)
                } catch (_: Exception) {
                }
                val next = queue.pollFirst()
                if (next != null) present(ctx, next.first, next.second)
            }.start()
        } catch (_: Exception) {
            try {
                wm?.removeView(v)
            } catch (_: Exception) {
            }
        }
    }
}
