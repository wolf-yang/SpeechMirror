package com.speechmirror.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import org.json.JSONObject

class SpeechMirrorAccessibilityService : AccessibilityService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var debounceWindows: Runnable? = null

    companion object {
        @Volatile
        var instance: SpeechMirrorAccessibilityService? = null

        @Volatile
        var lastKeyboardInsetPx: Int = 0

        private const val DEBOUNCE_MS = 400L
        private const val AUTO_SHOW_COOLDOWN_MS = 8000L

        @Volatile
        private var lastAutoShowElapsed: Long = 0L

        @Volatile
        private var lastAutoShowPackage: String? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        val info = serviceInfo
        info.flags = info.flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        serviceInfo = info
    }

    override fun onDestroy() {
        debounceWindows?.let { mainHandler.removeCallbacks(it) }
        if (instance === this) {
            instance = null
        }
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        scheduleDebounced()
    }

    override fun onInterrupt() {}

    private fun scheduleDebounced() {
        debounceWindows?.let { mainHandler.removeCallbacks(it) }
        val run = Runnable { processWindowsKeyboardAndAutoBubble() }
        debounceWindows = run
        mainHandler.postDelayed(run, DEBOUNCE_MS)
    }

    private fun processWindowsKeyboardAndAutoBubble() {
        val inset = computeKeyboardInsetFromWindows()
        lastKeyboardInsetPx = inset
        OverlayService.applyKeyboardInsetFromA11y(inset)
        maybeAutoShowBubbleForEditableFocus()
    }

    private fun computeKeyboardInsetFromWindows(): Int {
        return try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return 0
            val ws = windows ?: return 0
            val dm = resources.displayMetrics
            val screenH = dm.heightPixels
            var topMost = screenH
            for (w in ws) {
                try {
                    if (w.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD) {
                        val r = Rect()
                        w.getBoundsInScreen(r)
                        if (r.height() > 80 && r.top < topMost) {
                            topMost = r.top
                        }
                    }
                } finally {
                    try {
                        w.recycle()
                    } catch (_: Exception) {
                    }
                }
            }
            if (topMost >= screenH) return 0
            (screenH - topMost).coerceIn(0, screenH)
        } catch (_: Exception) {
            0
        }
    }

    private fun maybeAutoShowBubbleForEditableFocus() {
        if (!OverlayPrefs.isOverlayAutoShow(this)) return
        if (!OverlayPermissionChecker.mayShowBubble(this)) return
        val root = rootInActiveWindow ?: return
        val pkg = root.packageName?.toString() ?: return
        if (pkg == packageName) return
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return
        if (!focused.isEditable) {
            focused.recycle()
            return
        }
        focused.recycle()
        val now = SystemClock.elapsedRealtime()
        if (pkg == lastAutoShowPackage && now - lastAutoShowElapsed < AUTO_SHOW_COOLDOWN_MS) {
            return
        }
        lastAutoShowElapsed = now
        lastAutoShowPackage = pkg
        val intent = Intent(this, OverlayService::class.java).apply { action = OverlayService.ACTION_SHOW }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {
        }
    }

    fun pasteIntoFocused(text: String): Boolean {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("speechmirror", text))

        val root = rootInActiveWindow ?: return false
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: findEditable(root)
        return focused?.performAction(AccessibilityNodeInfo.ACTION_PASTE) ?: false
    }

    fun clickSendMapped(context: Context): Boolean {
        val root = rootInActiveWindow ?: return false
        val pkg = root.packageName?.toString() ?: return clickSendHeuristic(root)

        val jsonText = try {
            context.assets.open("send_button_map.json").bufferedReader().use { it.readText() }
        } catch (_: Exception) {
            return clickSendHeuristic(root)
        }

        return try {
            val obj = JSONObject(jsonText)
            val appObj = obj.optJSONObject(pkg) ?: return clickSendHeuristic(root)
            val candidates = appObj.optJSONArray("candidates") ?: return clickSendHeuristic(root)
            for (i in 0 until candidates.length()) {
                val c = candidates.optJSONObject(i) ?: continue
                val rid = c.optString("resourceId", "")
                val text = c.optString("text", "")
                if (rid.isNotBlank()) {
                    val list = root.findAccessibilityNodeInfosByViewId(rid)
                    if (!list.isNullOrEmpty()) {
                        for (n in list) {
                            if (clickNodeOrParent(n)) return true
                        }
                    }
                }
                if (text.isNotBlank() && dfsClickByText(root, text)) return true
            }
            clickSendHeuristic(root)
        } catch (_: Exception) {
            clickSendHeuristic(root)
        }
    }

    /**
     * 仅在用户从浮窗触发且开关开启时调用；限制节点数与深度。
     */
    fun collectChatContext(maxChars: Int): String {
        val root = rootInActiveWindow ?: return ""
        val sb = StringBuilder()
        val seen = HashSet<String>()
        val visits = intArrayOf(0)
        try {
            dfsCollect(root, sb, seen, depth = 0, maxDepth = 28, visits, maxVisits = 800, maxChars = maxChars)
        } finally {
            root.recycle()
        }
        var s = sb.toString().trim()
        if (s.length > maxChars) {
            s = s.substring(0, maxChars) + "\n…"
        }
        return s
    }

    private fun dfsCollect(
        node: AccessibilityNodeInfo,
        sb: StringBuilder,
        seen: HashSet<String>,
        depth: Int,
        maxDepth: Int,
        visits: IntArray,
        maxVisits: Int,
        maxChars: Int,
    ) {
        if (depth > maxDepth || sb.length >= maxChars || visits[0] >= maxVisits) return
        visits[0]++
        val t = node.text?.toString()?.trim().orEmpty()
        val cd = node.contentDescription?.toString()?.trim().orEmpty()
        val piece = when {
            t.length >= 2 && t !in seen -> t
            cd.length >= 2 && cd !in seen -> cd
            else -> ""
        }
        if (piece.isNotEmpty()) {
            seen.add(piece)
            if (sb.isNotEmpty()) sb.append('\n')
            sb.append(piece)
        }
        for (i in 0 until node.childCount) {
            if (visits[0] >= maxVisits || sb.length >= maxChars) break
            val ch = node.getChild(i) ?: continue
            dfsCollect(ch, sb, seen, depth + 1, maxDepth, visits, maxVisits, maxChars)
            ch.recycle()
        }
    }

    private fun clickSendHeuristic(root: AccessibilityNodeInfo): Boolean {
        return dfsClickByText(root, "发送")
    }

    private fun dfsClickByText(node: AccessibilityNodeInfo?, target: String): Boolean {
        if (node == null) return false
        val t = node.text?.toString() ?: ""
        val cd = node.contentDescription?.toString() ?: ""
        if ((t == target || cd == target) && clickNodeOrParent(node)) return true
        for (i in 0 until node.childCount) {
            if (dfsClickByText(node.getChild(i), target)) return true
        }
        return false
    }

    private fun clickNodeOrParent(start: AccessibilityNodeInfo): Boolean {
        var cur: AccessibilityNodeInfo? = start
        var depth = 0
        while (cur != null && depth < 10) {
            if (cur.isClickable && cur.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                return true
            }
            cur = cur.parent
            depth++
        }
        return false
    }

    private fun findEditable(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        return dfsEditable(root)
    }

    private fun dfsEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable) return node
        for (i in 0 until node.childCount) {
            val found = dfsEditable(node.getChild(i))
            if (found != null) return found
        }
        return null
    }
}
