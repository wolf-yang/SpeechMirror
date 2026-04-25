package com.speechmirror.app

import android.content.Context

/** 供无障碍 / 前台服务读取的开关镜像（主数据仍在 Flutter SQLite）。 */
object OverlayPrefs {
    private const val PREFS = "speechmirror_overlay_prefs"
    const val KEY_OVERLAY_AUTO = "overlay_auto_show"
    const val KEY_COLLECT = "collect_dialog_enabled"

    fun prefs(ctx: Context) = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isOverlayAutoShow(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_OVERLAY_AUTO, false)

    fun isCollectDialogEnabled(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_COLLECT, false)
}
