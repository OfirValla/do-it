package com.doit.app

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import com.doit.app.channel.EngineChannel
import com.doit.app.notifications.ReminderNotifier
import com.doit.app.receivers.DoItIntents
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Hosts Flutter and the platform channel. All scheduling lives in the
 * receivers/engine, so this activity is deliberately thin.
 *
 * When launched by a ringing alarm's full-screen intent it shows over the lock
 * screen and turns the screen on, like an alarm clock; the flags are dropped
 * again when the activity leaves the foreground.
 */
class MainActivity : FlutterActivity() {

    private var channel: EngineChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyLockScreenFlags(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ReminderNotifier.ensureChannels(this)
        channel = EngineChannel(this, flutterEngine.dartExecutor.binaryMessenger).also {
            it.attach()
            it.handleIntent(intent, coldStart = true)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.detach()
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyLockScreenFlags(intent)
        channel?.handleIntent(intent, coldStart = false)
    }

    override fun onStop() {
        super.onStop()
        setShowOverLockScreen(false)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        channel?.onRequestPermissionsResult(requestCode)
    }

    private fun applyLockScreenFlags(intent: Intent?) {
        if (intent?.getBooleanExtra(DoItIntents.EXTRA_FULL_SCREEN, false) == true) {
            setShowOverLockScreen(true)
        }
    }

    @Suppress("DEPRECATION")
    private fun setShowOverLockScreen(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled)
            setTurnScreenOn(enabled)
        } else {
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (enabled) window.addFlags(flags) else window.clearFlags(flags)
        }
    }
}
