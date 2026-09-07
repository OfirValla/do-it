package com.doit.app.channel

import android.os.Handler
import android.os.Looper

/**
 * Lets background components (receivers and the ring service running in the
 * same process) tell a live Flutter engine what changed. When no engine is
 * attached the calls are no-ops; Flutter re-reads everything on resume anyway.
 */
object FlutterBridge {
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var dataListener: (() -> Unit)? = null

    @Volatile
    private var ringingListener: ((Long?) -> Unit)? = null

    fun attach(onDataChanged: () -> Unit, onRingingChanged: (Long?) -> Unit) {
        dataListener = onDataChanged
        ringingListener = onRingingChanged
    }

    fun detach() {
        dataListener = null
        ringingListener = null
    }

    /** The shared database was modified by native code. */
    fun notifyDataChanged() {
        val current = dataListener ?: return
        mainHandler.post {
            // Re-check: the engine may have detached while the post was queued.
            if (dataListener === current) current()
        }
    }

    /** The alarm started ringing for [reminderId], or stopped (null). */
    fun notifyRinging(reminderId: Long?) {
        val current = ringingListener ?: return
        mainHandler.post {
            if (ringingListener === current) current(reminderId)
        }
    }
}
