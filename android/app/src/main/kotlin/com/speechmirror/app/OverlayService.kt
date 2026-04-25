package com.speechmirror.app

import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.MotionEvent
import android.view.Gravity
import android.view.View
import android.view.ViewConfiguration
import android.view.animation.DecelerateInterpolator
import android.view.WindowManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout.LayoutParams
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.view.inputmethod.InputMethodManager
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.MethodChannel

class OverlayService : Service() {
    companion object {
        private const val TAG = "OverlayService"
        const val ACTION_SHOW = "com.speechmirror.app.overlay.SHOW"
        const val ACTION_HIDE = "com.speechmirror.app.overlay.HIDE"
        const val ACTION_EXPAND = "com.speechmirror.app.overlay.EXPAND"
        private const val NOTIF_ID = 1001
        private const val CHANNEL_ID = "sm_overlay"
        private const val PANEL_CHANNEL = "com.speechmirror.app/overlay_panel"

        @Volatile
        var instance: OverlayService? = null

        /** 由无障碍线程估算键盘高度后，在主线程调整浮窗面板高度（不启动 Service）。 */
        @JvmStatic
        fun applyKeyboardInsetFromA11y(insetBottomPx: Int) {
            val svc = instance ?: return
            Handler(Looper.getMainLooper()).post {
                svc.applyOuterKeyboardInsetPx(insetBottomPx.coerceAtLeast(0))
            }
        }
    }

    private var bubbleRoot: FrameLayout? = null
    private var bubbleParams: WindowManager.LayoutParams? = null

    private var panelRoot: FrameLayout? = null
    private var panelParams: WindowManager.LayoutParams? = null
    private var panelBarView: LinearLayout? = null
    private var panelInputView: EditText? = null
    private var panelResultsContainer: LinearLayout? = null
    private var panelResultsScroll: ScrollView? = null
    private var panelResultsCard: LinearLayout? = null
    private var panelConvertIcon: ImageView? = null
    private var panelConvertSpinner: ProgressBar? = null
    private var panelBaseHeightPx: Int = 0
    private var panelMode: String = "idle"
    private var compactConvertTimeout: Runnable? = null

    private var flutterRoot: FrameLayout? = null
    private var flutterParams: WindowManager.LayoutParams? = null
    private var flutterView: FlutterView? = null
    private var flutterEngine: FlutterEngine? = null
    private var panelChannel: MethodChannel? = null
    private var panelLoadingView: FrameLayout? = null
    private var panelUiDisplayListener: FlutterUiDisplayListener? = null
    private var panelFirstFrameTimeout: Runnable? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var panelEngineWarm = false
    private var panelEntrypointExecuted = false
    private var panelPrewarmStarted = false
    private var pendingTopInputText: String? = null
    private var pendingTopInputAutoConvert = false
    private var pendingPanelMode: String = "full"
    private var currentPanelMode: String = "full"
    private var imeRequestSeq = 0

    private fun wm(): WindowManager = getSystemService(WINDOW_SERVICE) as WindowManager

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_HIDE -> {
                hideTopBarPanel()
                hideFlutterPanel()
                removeBubble()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(Service.STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SHOW -> {
                ensureChannel()
                startForeground(NOTIF_ID, buildNotification())
                showBubble()
                // 预热第二引擎，减少首次展开超时概率。
                mainHandler.post { ensurePanelEnginePrepared() }
                return START_STICKY
            }
            ACTION_EXPAND -> {
                showTopBarPanel()
                return START_STICKY
            }
        }
        return START_NOT_STICKY
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        hideTopBarPanel()
        hideFlutterPanel()
        removeBubble()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(Service.STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun applyOuterKeyboardInsetPx(insetBottomPx: Int) {
        val params = flutterParams ?: return
        val dm = resources.displayMetrics
        val density = dm.density
        val screenH = dm.heightPixels
        val base = (screenH * 0.48f).toInt()
        val minH = (250 * density).toInt()
        val maxInset = (screenH * 0.45f).toInt()
        val capped = insetBottomPx.coerceIn(0, maxInset)
        val targetH = (base - capped).coerceAtLeast(minH)
        if (params.height == targetH) return
        params.height = targetH
        flutterParams = params
        flutterRoot?.let {
            try {
                wm().updateViewLayout(it, params)
            } catch (_: Exception) {
            }
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val ch = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.overlay_channel_name),
                NotificationManager.IMPORTANCE_MIN,
            )
            nm.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("语镜")
            .setContentText("悬浮球运行中")
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .build()
    }

    private fun showBubble() {
        if (bubbleRoot != null) return
        val windowManager = wm()

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val dm = resources.displayMetrics
        val density = dm.density
        val size = (30 * density).toInt().coerceAtLeast(40)

        val params = WindowManager.LayoutParams(
            size,
            size,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        )
        // TOP|START：x/y 为左上坐标，便于拖动与 updateViewLayout
        params.gravity = Gravity.TOP or Gravity.START
        params.x = (dm.widthPixels - size - (16 * density).toInt()).coerceAtLeast(0)
        params.y = (120 * density).toInt()
        val root = FrameLayout(this)
        root.setBackgroundResource(R.drawable.overlay_bubble_bg)

        val tv = TextView(this).apply {
            text = "语"
            textSize = 13f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = android.view.Gravity.CENTER
        }
        root.addView(
            tv,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        val wm = windowManager
        val dragSlop = ViewConfiguration.get(this).scaledTouchSlop
        var downRawX = 0f
        var downRawY = 0f
        var startX = 0
        var startY = 0
        var dragging = false

        root.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startX = params.x
                    startY = params.y
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downRawX).toInt()
                    val dy = (event.rawY - downRawY).toInt()
                    if (!dragging && (kotlin.math.abs(dx) > dragSlop || kotlin.math.abs(dy) > dragSlop)) {
                        dragging = true
                    }
                    if (dragging) {
                        val maxX = (dm.widthPixels - size).coerceAtLeast(0)
                        val maxY = (dm.heightPixels - size).coerceAtLeast(0)
                        params.x = (startX + dx).coerceIn(0, maxX)
                        params.y = (startY + dy).coerceIn(0, maxY)
                        try {
                            wm.updateViewLayout(root, params)
                        } catch (_: Exception) {
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!dragging) {
                        showTopBarPanel()
                    } else {
                        val targetX = if (params.x + size / 2 < dm.widthPixels / 2) {
                            0
                        } else {
                            (dm.widthPixels - size).coerceAtLeast(0)
                        }
                        animateBubbleEdgeSnap(root, params, targetX)
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    true
                }
                else -> false
            }
        }

        bubbleRoot = root
        bubbleParams = params
        windowManager.addView(root, params)
    }

    private fun showTopBarPanel() {
        if (panelRoot != null) return
        hideFlutterPanel()
        removeBubble()
        val windowManager = wm()
        val dm = resources.displayMetrics
        val density = dm.density
        val panelH = (56 * density).toInt().coerceAtLeast(52)
        val outerMargin = (12 * density).toInt()
        val panelW = (dm.widthPixels * 0.92f).toInt().coerceAtLeast((260 * density).toInt())
        val corner = (panelH / 2f)
        val statusBarH = statusBarHeightPx()

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            isClickable = true
        }

        val lp = WindowManager.LayoutParams(
            panelW,
            panelH + outerMargin * 2,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        )
        lp.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        lp.gravity = Gravity.TOP or Gravity.START
        val startX = ((dm.widthPixels - panelW) / 2).coerceAtLeast(0)
        val startY = statusBarH + outerMargin
        lp.x = startX
        lp.y = startY
        panelBaseHeightPx = panelH + outerMargin * 2

        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((14 * density).toInt(), 0, (14 * density).toInt(), 0)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = corner
                setColor(0xFCF8FAFC.toInt())
                setStroke((1 * density).toInt().coerceAtLeast(1), 0xFFD8DEE6.toInt())
            }
            elevation = 6 * density
        }
        val barLp = FrameLayout.LayoutParams(
            panelW - outerMargin * 2,
            panelH,
            Gravity.TOP,
        )
        barLp.leftMargin = outerMargin
        barLp.rightMargin = outerMargin

        val input = EditText(this).apply {
            hint = "待输入"
            isFocusable = true
            isFocusableInTouchMode = true
            setSingleLine(true)
            setBackgroundColor(Color.TRANSPARENT)
            setTextColor(0xFF0F172A.toInt())
            setHintTextColor(0xFF94A3B8.toInt())
            textSize = 13f
            setPadding(0, 0, 0, 0)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        input.onFocusChangeListener = View.OnFocusChangeListener { _, hasFocus ->
            updateTopBarFocusMode(root, lp, hasFocus)
            if (hasFocus) {
                requestImeWhenServed(input, root, lp, maxRetries = 4)
            } else {
                hideImeNow(input)
            }
        }
        input.setOnClickListener {
            if (!input.isFocused) {
                input.requestFocus()
            }
        }
        panelInputView = input
        val convert = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_send)
            setColorFilter(0xFF2B4C7E.toInt())
            setPadding((6 * density).toInt(), (6 * density).toInt(), (6 * density).toInt(), (6 * density).toInt())
            setOnClickListener {
                val text = panelInputView?.text?.toString()?.trim().orEmpty()
                if (text.isEmpty()) {
                    showInlineMessage("待输入后可转换")
                    return@setOnClickListener
                }
                input.clearFocus()
                hideImeNow(input)
                startCompactConvert(text)
            }
        }
        panelConvertIcon = convert
        val spinner = ProgressBar(this).apply {
            visibility = View.GONE
            isIndeterminate = true
        }
        val spinnerSize = (18 * density).toInt().coerceAtLeast(16)
        val convertSlot = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams((30 * density).toInt(), (30 * density).toInt())
            addView(
                convert,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    Gravity.CENTER,
                ),
            )
            addView(
                spinner,
                FrameLayout.LayoutParams(
                    spinnerSize,
                    spinnerSize,
                    Gravity.CENTER,
                ),
            )
        }
        panelConvertSpinner = spinner
        val expand = ImageView(this).apply {
            setImageResource(android.R.drawable.arrow_down_float)
            setColorFilter(0xFF2B4C7E.toInt())
            setPadding((6 * density).toInt(), (6 * density).toInt(), (6 * density).toInt(), (6 * density).toInt())
            setOnClickListener {
                input.clearFocus()
                hideImeNow(input)
                hideTopBarPanel()
                openMainAppHome()
            }
        }
        bar.addView(input)
        bar.addView(spaceView((6 * density).toInt()))
        bar.addView(convertSlot)
        bar.addView(spaceView((6 * density).toInt()))
        bar.addView(expand)
        root.addView(bar, barLp)
        val results = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, 0, 0)
        }
        val resultCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding((12 * density).toInt(), (10 * density).toInt(), (12 * density).toInt(), (10 * density).toInt())
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = corner
                setColor(0xEEF8FAFC.toInt())
                setStroke((1 * density).toInt().coerceAtLeast(1), 0xFFD8DEE6.toInt())
            }
            elevation = 5 * density
            visibility = View.GONE
            alpha = 1f
            addView(
                results,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
        val scroll = ScrollView(this).apply {
            visibility = View.VISIBLE
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            setPadding((outerMargin + 4), (outerMargin + panelH + 6), (outerMargin + 4), 4)
            addView(
                resultCard,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
        root.addView(
            scroll,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP,
            ),
        )
        panelResultsContainer = results
        panelResultsScroll = scroll
        panelResultsCard = resultCard

        val dragSlop = ViewConfiguration.get(this).scaledTouchSlop
        var downX = 0f
        var downY = 0f
        var baseX = startX
        var baseY = startY
        var dragging = false
        val peekRatio = 0.1f
        val minX = -(panelW * peekRatio).toInt()
        val maxX = (dm.widthPixels - (panelW * (1f - peekRatio)).toInt())
        val minY = (statusBarH - (24 * density).toInt()).coerceAtLeast(0)
        val xRange = (maxX - minX).coerceAtLeast(1)
        val yRange = (startY - minY).coerceAtLeast(1)
        val dismissX = kotlin.math.max((xRange * 0.55f).toInt(), (24 * density).toInt())
            .coerceAtMost((96 * density).toInt())
        val dismissY = kotlin.math.max((yRange * 0.6f).toInt(), (24 * density).toInt())
            .coerceAtMost((72 * density).toInt())
        val minAlpha = 0.28f
        val maxY = (dm.heightPixels * 0.45f).toInt()
        var downOnInput = false
        var inputDragOverride = false
        bar.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    baseX = lp.x
                    baseY = lp.y
                    downOnInput = isPointInsideView(event.rawX, event.rawY, input)
                    inputDragOverride = false
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downX).toInt()
                    val dy = (event.rawY - downY).toInt()
                    if (downOnInput && !inputDragOverride) {
                        if (kotlin.math.abs(dx) <= dragSlop && kotlin.math.abs(dy) <= dragSlop) {
                            // 仍由 bar 持有事件流，避免后续 MOVE/UP 被输入框截走导致无法拖拽划走。
                            return@setOnTouchListener true
                        }
                        inputDragOverride = true
                    }
                    if (!dragging && (kotlin.math.abs(dx) > dragSlop || kotlin.math.abs(dy) > dragSlop)) {
                        dragging = true
                    }
                    if (dragging) {
                        lp.x = (baseX + dx).coerceIn(minX, maxX)
                        lp.y = (baseY + dy).coerceIn(minY, maxY)
                        try {
                            windowManager.updateViewLayout(root, lp)
                        } catch (_: Exception) {
                        }
                        val p = panelDismissProgress(lp.x, lp.y, startX, startY, dismissX, dismissY)
                        applyPanelVisualProgress((1f - 0.72f * p).coerceAtLeast(minAlpha))
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (!dragging) {
                        if (downOnInput && event.actionMasked == MotionEvent.ACTION_UP) {
                            if (!input.isFocused) {
                                input.requestFocus()
                            }
                            input.performClick()
                        }
                        return@setOnTouchListener downOnInput
                    }
                    updateTopBarFocusMode(root, lp, false)
                    val totalDx = event.rawX - downX
                    val totalDy = event.rawY - downY
                    val reachX = kotlin.math.abs(totalDx) >= dismissX
                    val reachY = (-totalDy) >= dismissY
                    if (reachX || reachY) {
                        hideTopBarPanel()
                        showBubble()
                    } else {
                        animateBarBack(root, lp, bar, startX, startY, panelResultsCard)
                    }
                    true
                }
                else -> false
            }
        }

        val resultDismissX = kotlin.math.max((panelW * 0.22f).toInt(), (22 * density).toInt())
        val resultDismissY = kotlin.math.max((panelH * 0.35f).toInt(), (20 * density).toInt())
        var resultDownX = 0f
        var resultDownY = 0f
        var resultDragging = false
        val resultCardRef = resultCard
        resultCardRef.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    resultDownX = event.rawX
                    resultDownY = event.rawY
                    resultDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - resultDownX
                    val dy = event.rawY - resultDownY
                    if (!resultDragging && (kotlin.math.abs(dx) > dragSlop || kotlin.math.abs(dy) > dragSlop)) {
                        resultDragging = true
                    }
                    if (!resultDragging) return@setOnTouchListener true
                    v.translationX = dx * 0.9f
                    v.translationY = dy * 0.55f
                    val p = kotlin.math.max(
                        kotlin.math.abs(dx) / resultDismissX.toFloat(),
                        kotlin.math.max(0f, -dy) / resultDismissY.toFloat(),
                    ).coerceIn(0f, 1f)
                    v.alpha = (1f - 0.68f * p).coerceAtLeast(0.25f)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (!resultDragging) return@setOnTouchListener false
                    val reachX = kotlin.math.abs(v.translationX) >= resultDismissX
                    val reachY = (-v.translationY) >= resultDismissY
                    if (reachX || reachY) {
                        hideInlineResults()
                    } else {
                        animateResultCardBack(v)
                    }
                    true
                }
                else -> false
            }
        }

        windowManager.addView(root, lp)
        panelRoot = root
        panelParams = lp
        panelBarView = bar
        panelMode = "idle"
    }

    private fun animateBubbleEdgeSnap(
        root: FrameLayout,
        params: WindowManager.LayoutParams,
        targetX: Int,
    ) {
        val fromX = params.x
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 180L
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val t = animator.animatedFraction
                params.x = (fromX + (targetX - fromX) * t).toInt()
                try {
                    wm().updateViewLayout(root, params)
                } catch (_: Exception) {
                }
            }
        }.start()
    }

    private fun animateBarBack(
        root: FrameLayout,
        params: WindowManager.LayoutParams,
        bar: LinearLayout,
        targetX: Int,
        targetY: Int,
        resultCard: View?,
    ) {
        val fromX = params.x
        val fromY = params.y
        val fromA = bar.alpha
        val fromResultA = resultCard?.alpha ?: 1f
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 180L
            addUpdateListener { animator ->
                val t = animator.animatedFraction
                params.x = (fromX + (targetX - fromX) * t).toInt()
                params.y = (fromY + (targetY - fromY) * t).toInt()
                bar.alpha = fromA + (1f - fromA) * t
                resultCard?.alpha = fromResultA + (1f - fromResultA) * t
                try {
                    wm().updateViewLayout(root, params)
                } catch (_: Exception) {
                }
            }
        }.start()
    }

    private fun panelDismissProgress(
        x: Int,
        y: Int,
        startX: Int,
        startY: Int,
        dismissX: Int,
        dismissY: Int,
    ): Float {
        val pX = kotlin.math.abs(x - startX).toFloat() / dismissX.toFloat().coerceAtLeast(1f)
        val pY = kotlin.math.max(0, startY - y).toFloat() / dismissY.toFloat().coerceAtLeast(1f)
        return kotlin.math.max(pX, pY).coerceIn(0f, 1f)
    }

    private fun applyPanelVisualProgress(alpha: Float) {
        panelBarView?.alpha = alpha
        panelResultsCard?.alpha = alpha
    }

    private fun animateResultCardBack(card: View) {
        val fromX = card.translationX
        val fromY = card.translationY
        val fromA = card.alpha
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 170L
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val t = animator.animatedFraction
                card.translationX = fromX * (1f - t)
                card.translationY = fromY * (1f - t)
                card.alpha = fromA + (1f - fromA) * t
            }
        }.start()
    }

    private fun hideInlineResults() {
        panelResultsContainer?.removeAllViews()
        panelResultsCard?.apply {
            alpha = 1f
            translationX = 0f
            translationY = 0f
            visibility = View.GONE
        }
        updateTopBarPanelHeight(extraDp = 0)
    }

    private fun hideTopBarPanel() {
        imeRequestSeq++
        panelInputView?.clearFocus()
        panelInputView?.let { hideImeNow(it) }
        compactConvertTimeout?.let { mainHandler.removeCallbacks(it) }
        compactConvertTimeout = null
        val windowManager = wm()
        panelRoot?.let {
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {
            }
        }
        panelRoot = null
        panelParams = null
        panelBarView = null
        panelInputView = null
        panelResultsContainer = null
        panelResultsScroll = null
        panelResultsCard = null
        panelConvertIcon = null
        panelConvertSpinner = null
        panelMode = "idle"
    }

    private fun showFlutterPanel() {
        val mode = "full"
        if (flutterRoot != null && currentPanelMode == mode) {
            return
        }
        if (flutterRoot != null && currentPanelMode != mode) {
            hideFlutterPanel()
        }
        val t0 = android.os.SystemClock.elapsedRealtime()
        if (mode == "full") {
            imeRequestSeq++
            panelInputView?.clearFocus()
            panelInputView?.let { hideImeNow(it) }
            hideTopBarPanel()
            removeBubble()
        }
        currentPanelMode = mode
        val windowManager = wm()
        Log.d(TAG, "showFlutterPanel: begin")

        val engine = ensurePanelEnginePrepared()
        Log.d(TAG, "showFlutterPanel: engine prepared in ${android.os.SystemClock.elapsedRealtime() - t0}ms")
        OverlayFlutterChannel.install(engine.dartExecutor.binaryMessenger, this)
        panelChannel = MethodChannel(engine.dartExecutor.binaryMessenger, PANEL_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "closePanel" -> {
                        hideFlutterPanel()
                        showBubble()
                        result.success(null)
                    }
                    "openMainApp" -> {
                        val launch = packageManager.getLaunchIntentForPackage(packageName)
                        if (launch != null) {
                            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            startActivity(launch)
                        }
                        result.success(null)
                    }
                    "consumeOverlayLaunchPayload" -> {
                        result.success(
                            mapOf(
                                "mode" to pendingPanelMode,
                                "text" to (pendingTopInputText ?: ""),
                                "autoConvert" to pendingTopInputAutoConvert,
                            ),
                        )
                        pendingTopInputText = null
                        pendingTopInputAutoConvert = false
                    }
                    else -> result.notImplemented()
                }
            }
        }

        val textureView = FlutterTextureView(this)
        val fv = FlutterView(this, textureView).apply {
            setBackgroundColor(0xFFF8FAFC.toInt())
            attachToFlutterEngine(engine)
        }

        val dm = resources.displayMetrics
        val density = dm.density
        val statusBarH = statusBarHeightPx()
        val panelH = (dm.heightPixels * 0.48f).toInt().coerceAtLeast((280 * density).toInt())
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            panelH,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        )
        lp.gravity = Gravity.TOP or Gravity.START
        lp.x = 0
        lp.y = statusBarH + (8 * density).toInt()

        val root = FrameLayout(this).apply {
            setBackgroundColor(0x5A0F172A.toInt())
            addView(
                fv,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }

        val loadingView = FrameLayout(this).apply {
            setBackgroundColor(0x33000000)
            isClickable = true
            addView(
                LinearLayout(this@OverlayService).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(24, 16, 24, 16)
                    background = GradientDrawable().apply {
                        cornerRadius = 24f
                        setColor(0xF8FFFFFF.toInt())
                    }
                    addView(ProgressBar(this@OverlayService))
                    addView(TextView(this@OverlayService).apply {
                        text = "加载中..."
                        setTextColor(0xFF334155.toInt())
                        setPadding(14, 0, 0, 0)
                    })
                },
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER,
                ),
            )
        }
        root.addView(
            loadingView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        panelUiDisplayListener = object : FlutterUiDisplayListener {
            override fun onFlutterUiDisplayed() {
                panelFirstFrameTimeout?.let { mainHandler.removeCallbacks(it) }
                panelFirstFrameTimeout = null
                panelEngineWarm = true
                Log.d(TAG, "showFlutterPanel: first frame shown in ${android.os.SystemClock.elapsedRealtime() - t0}ms")
                panelLoadingView?.let {
                    try {
                        root.removeView(it)
                    } catch (_: Exception) {
                    }
                }
                panelLoadingView = null
            }

            override fun onFlutterUiNoLongerDisplayed() = Unit
        }
        fv.addOnFirstFrameRenderedListener(panelUiDisplayListener!!)

        windowManager.addView(root, lp)
        flutterRoot = root
        flutterParams = lp
        flutterView = fv
        flutterEngine = engine
        panelLoadingView = loadingView

        panelFirstFrameTimeout?.let { mainHandler.removeCallbacks(it) }
        panelFirstFrameTimeout = Runnable {
            if (panelLoadingView != null) {
                Log.w(TAG, "showFlutterPanel: first frame timeout, fallback to top bar")
                hideFlutterPanel()
                showTopBarPanel()
                android.widget.Toast.makeText(this, "浮窗加载失败，已返回顶部条", android.widget.Toast.LENGTH_SHORT).show()
            }
        }
        val timeoutMs = if (panelEngineWarm) 6000L else 12000L
        Log.d(TAG, "showFlutterPanel: timeout=${timeoutMs}ms, warm=$panelEngineWarm")
        mainHandler.postDelayed(panelFirstFrameTimeout!!, timeoutMs)
        applyOuterKeyboardInsetPx(SpeechMirrorAccessibilityService.lastKeyboardInsetPx)
    }

    private fun openMainAppHome() {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            startActivity(launch)
        }
    }

    private fun hideFlutterPanel() {
        panelFirstFrameTimeout?.let { mainHandler.removeCallbacks(it) }
        panelFirstFrameTimeout = null
        panelUiDisplayListener?.let { listener ->
            try {
                flutterView?.removeOnFirstFrameRenderedListener(listener)
            } catch (_: Exception) {
            }
        }
        panelUiDisplayListener = null
        flutterView?.detachFromFlutterEngine()
        flutterRoot?.let {
            try {
                wm().removeView(it)
            } catch (_: Exception) {
            }
        }
        panelChannel?.setMethodCallHandler(null)
        panelChannel = null
        panelLoadingView = null
        flutterRoot = null
        flutterParams = null
        flutterView = null
    }

    private fun startCompactConvert(text: String) {
        if (panelMode == "converting") return
        panelMode = "converting"
        setConvertLoading(true)
        hideInlineResults()
        compactConvertTimeout?.let { mainHandler.removeCallbacks(it) }
        compactConvertTimeout = Runnable {
            if (panelMode == "converting") {
                showInlineMessage("当前思考时间较长")
            }
        }
        mainHandler.postDelayed(compactConvertTimeout!!, 30000L)
        val engine = ensurePanelEnginePrepared()
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, PANEL_CHANNEL)
        ch.invokeMethod(
            "startCompactConvert",
            mapOf("text" to text),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    mainHandler.post {
                        compactConvertTimeout?.let { mainHandler.removeCallbacks(it) }
                        compactConvertTimeout = null
                        setConvertLoading(false)
                        panelMode = "idle"
                        val map = result as? Map<*, *>
                        val ok = map?.get("ok") == true
                        if (!ok) {
                            showInlineMessage(map?.get("error")?.toString() ?: "转换失败")
                            return@post
                        }
                        val variantsRaw = map["variants"] as? List<*> ?: emptyList<Any?>()
                        val variants = variantsRaw.mapNotNull { any ->
                            val item = any as? Map<*, *> ?: return@mapNotNull null
                            val label = item["label"]?.toString()?.trim().orEmpty()
                            val value = item["text"]?.toString()?.trim().orEmpty()
                            if (value.isEmpty()) return@mapNotNull null
                            Pair(if (label.isEmpty()) "候选" else label, value)
                        }.take(3)
                        if (variants.isEmpty()) {
                            showInlineMessage("模型未返回可用结果")
                        } else {
                            showInlineVariants(variants)
                        }
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    mainHandler.post {
                        compactConvertTimeout?.let { mainHandler.removeCallbacks(it) }
                        compactConvertTimeout = null
                        setConvertLoading(false)
                        panelMode = "idle"
                        showInlineMessage(errorMessage ?: "转换失败($errorCode)")
                    }
                }

                override fun notImplemented() {
                    mainHandler.post {
                        compactConvertTimeout?.let { mainHandler.removeCallbacks(it) }
                        compactConvertTimeout = null
                        setConvertLoading(false)
                        panelMode = "idle"
                        showInlineMessage("后台转换通道未实现")
                    }
                }
            },
        )
    }

    private fun setConvertLoading(loading: Boolean) {
        val icon = panelConvertIcon ?: return
        val spinner = panelConvertSpinner ?: return
        if (loading) {
            icon.visibility = View.INVISIBLE
            spinner.visibility = View.VISIBLE
        } else {
            spinner.visibility = View.GONE
            icon.visibility = View.VISIBLE
        }
    }

    private fun showInlineMessage(message: String) {
        val container = panelResultsContainer ?: return
        container.removeAllViews()
        panelResultsCard?.apply {
            visibility = View.VISIBLE
            alpha = 1f
            translationX = 0f
            translationY = 0f
        }
        val tv = TextView(this).apply {
            text = message
            textSize = 13f
            setTextColor(0xFF334155.toInt())
            setPadding(12, 10, 12, 10)
            background = GradientDrawable().apply {
                cornerRadius = 14f
                setColor(0xFFF1F5F9.toInt())
                setStroke(1, 0xFFD7E2EE.toInt())
            }
        }
        container.addView(tv)
        updateTopBarPanelHeight(extraDp = 72)
        refreshPanelHeightForResults()
    }

    private fun showInlineVariants(variants: List<Pair<String, String>>) {
        val container = panelResultsContainer ?: return
        container.removeAllViews()
        panelResultsCard?.apply {
            visibility = View.VISIBLE
            alpha = 1f
            translationX = 0f
            translationY = 0f
        }
        for ((label, text) in variants) {
            val card = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(12, 10, 12, 8)
                background = GradientDrawable().apply {
                    cornerRadius = 14f
                    setColor(0xFFF1F5F9.toInt())
                    setStroke(1, 0xFFD7E2EE.toInt())
                }
                val lp = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
                lp.bottomMargin = 8
                layoutParams = lp
            }
            val title = TextView(this).apply {
                this.text = label
                textSize = 12f
                setTextColor(0xFF1E293B.toInt())
            }
            val body = TextView(this).apply {
                this.text = text
                textSize = 14f
                setTextColor(0xFF1E293B.toInt())
            }
            val actions = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, (8 * resources.displayMetrics.density).toInt(), 0, 0)
            }
            val copy = TextView(this).apply {
                this.text = "复制"
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(0xFF1D4E89.toInt())
                setPadding(0, 0, 0, 0)
                background = GradientDrawable().apply {
                    cornerRadii = floatArrayOf(
                        10f, 10f,
                        0f, 0f,
                        0f, 0f,
                        10f, 10f,
                    )
                    setColor(0xFFE8F1FD.toInt())
                    setStroke(1, 0xFFC8DBF5.toInt())
                }
                layoutParams = LinearLayout.LayoutParams(0, (36 * resources.displayMetrics.density).toInt(), 1f)
                setOnClickListener {
                    val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("overlay_text", text))
                    android.widget.Toast.makeText(this@OverlayService, "已复制", android.widget.Toast.LENGTH_SHORT).show()
                }
            }
            val fill = TextView(this).apply {
                this.text = "填充"
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(0xFF1D4E89.toInt())
                setPadding(0, 0, 0, 0)
                background = GradientDrawable().apply {
                    cornerRadii = floatArrayOf(
                        0f, 0f,
                        10f, 10f,
                        10f, 10f,
                        0f, 0f,
                    )
                    setColor(0xFFE8F1FD.toInt())
                    setStroke(1, 0xFFC8DBF5.toInt())
                }
                layoutParams = LinearLayout.LayoutParams(0, (36 * resources.displayMetrics.density).toInt(), 1f)
                setOnClickListener {
                    val ok = SpeechMirrorAccessibilityService.instance?.pasteIntoFocused(text) ?: false
                    if (!ok) {
                        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        cm.setPrimaryClip(ClipData.newPlainText("overlay_text", text))
                    }
                    android.widget.Toast.makeText(this@OverlayService, if (ok) "已填充" else "未检测到输入框，已复制", android.widget.Toast.LENGTH_SHORT).show()
                }
            }
            actions.addView(copy)
            actions.addView(fill)
            card.addView(title)
            card.addView(body)
            card.addView(actions)
            container.addView(card)
        }
        updateTopBarPanelHeight(extraDp = (variants.size * 102 + 18))
        refreshPanelHeightForResults()
    }

    private fun updateTopBarPanelHeight(extraDp: Int) {
        val root = panelRoot ?: return
        val lp = panelParams ?: return
        val density = resources.displayMetrics.density
        val maxExtra = (resources.displayMetrics.heightPixels * 0.62f).toInt()
        val target = panelBaseHeightPx + (extraDp * density).toInt().coerceAtMost(maxExtra)
        if (lp.height == target) return
        lp.height = target
        panelParams = lp
        try {
            wm().updateViewLayout(root, lp)
        } catch (_: Exception) {
        }
    }

    private fun refreshPanelHeightForResults() {
        val card = panelResultsCard ?: return
        card.post {
            val measured = card.height.takeIf { it > 0 } ?: return@post
            val density = resources.displayMetrics.density
            val dynamicExtraDp = (measured / density).toInt() + 14
            updateTopBarPanelHeight(extraDp = dynamicExtraDp)
        }
    }

    private fun removeBubble() {
        val windowManager = wm()
        val v = bubbleRoot ?: return
        try {
            windowManager.removeView(v)
        } catch (_: Exception) {
        }
        bubbleRoot = null
        bubbleParams = null
    }

    override fun onDestroy() {
        hideTopBarPanel()
        hideFlutterPanel()
        removeBubble()
        if (instance === this) {
            instance = null
        }
        super.onDestroy()
    }

    private fun statusBarHeightPx(): Int {
        val density = resources.displayMetrics.density
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else (24 * density).toInt()
    }

    private fun spaceView(widthPx: Int): View {
        return View(this).apply {
            layoutParams = LinearLayout.LayoutParams(widthPx, 1)
        }
    }

    private fun updateTopBarFocusMode(
        root: FrameLayout,
        lp: WindowManager.LayoutParams,
        focused: Boolean,
    ) {
        val oldFlags = lp.flags
        lp.flags = if (focused) {
            (lp.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv())
        } else {
            (lp.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)
        }
        lp.softInputMode = if (focused) {
            WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE
        } else {
            WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
        if (oldFlags == lp.flags && !focused) return
        try {
            wm().updateViewLayout(root, lp)
            Log.d(TAG, "updateTopBarFocusMode: focused=$focused flags=${lp.flags}")
        } catch (_: Exception) {
        }
    }

    private fun requestImeWhenServed(
        input: EditText,
        root: FrameLayout,
        lp: WindowManager.LayoutParams,
        maxRetries: Int,
    ) {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager ?: return
        val seq = ++imeRequestSeq
        var remaining = maxRetries
        fun attempt() {
            if (seq != imeRequestSeq) return
            val ready = input.windowToken != null &&
                input.isShown &&
                input.hasFocus() &&
                root.isAttachedToWindow &&
                root.hasWindowFocus()
            if (!ready) {
                if (remaining > 0) {
                    remaining--
                    if (input.hasFocus()) {
                        updateTopBarFocusMode(root, lp, true)
                    }
                    input.postDelayed({ attempt() }, 60L)
                }
                return
            }
            imm.restartInput(input)
            val shown = imm.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
            if (!shown && remaining > 0) {
                remaining--
                // 再次确保窗口处于可聚焦态后重试，规避“is not served”时序竞争。
                updateTopBarFocusMode(root, lp, true)
                input.postDelayed({ attempt() }, 80L)
            }
        }
        input.post { attempt() }
    }

    private fun hideImeNow(target: View) {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager ?: return
        try {
            imm.hideSoftInputFromWindow(target.windowToken, 0)
        } catch (_: Exception) {
        }
    }

    private fun isPointInsideView(rawX: Float, rawY: Float, view: View): Boolean {
        val loc = IntArray(2)
        view.getLocationOnScreen(loc)
        val x = rawX.toInt()
        val y = rawY.toInt()
        return x >= loc[0] && x <= loc[0] + view.width && y >= loc[1] && y <= loc[1] + view.height
    }

    private fun ensurePanelEnginePrepared(): FlutterEngine {
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(applicationContext)
        }
        loader.ensureInitializationComplete(applicationContext, null)
        val engine = flutterEngine ?: FlutterEngine(applicationContext).also {
            flutterEngine = it
            panelEngineWarm = false
            panelEntrypointExecuted = false
            Log.d(TAG, "ensurePanelEnginePrepared: created new engine")
        }
        if (!panelEntrypointExecuted && !panelPrewarmStarted) {
            panelPrewarmStarted = true
            val tEntry = android.os.SystemClock.elapsedRealtime()
            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "package:speechmirror/overlay_main.dart",
                "overlayMain",
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint)
            panelEntrypointExecuted = true
            panelPrewarmStarted = false
            Log.d(TAG, "ensurePanelEnginePrepared: executeDartEntrypoint cost ${android.os.SystemClock.elapsedRealtime() - tEntry}ms")
        }
        return engine
    }

}
