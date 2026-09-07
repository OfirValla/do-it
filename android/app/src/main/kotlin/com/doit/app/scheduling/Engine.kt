package com.doit.app.scheduling

import android.content.BroadcastReceiver
import android.content.Context
import android.util.Log
import com.doit.app.channel.FlutterBridge
import com.doit.app.db.SqliteReminderStore
import com.doit.app.notifications.ReminderNotifier
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Builds a fully wired [ReminderEngine] for the given context and runs work on a
 * single background thread so database access from several receivers is
 * serialised.
 */
object Engine {
    private const val TAG = "DoIt.Engine"

    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "doit-engine").apply { isDaemon = false }
    }

    private val logger = object : EngineLogger {
        override fun d(message: String) {
            Log.d(TAG, message)
        }

        override fun w(message: String, error: Throwable?) {
            Log.w(TAG, message, error)
        }
    }

    /**
     * Opens the shared database, runs [block] with an engine, closes the
     * database. Returns false if the database does not exist yet.
     */
    fun <T> withEngine(context: Context, block: (ReminderEngine) -> T): T? {
        val appContext = context.applicationContext
        val store = SqliteReminderStore.openIfExists(appContext) ?: return null
        return store.use {
            val engine = ReminderEngine(
                store = it,
                alarms = AndroidAlarmGateway(appContext),
                notifier = ReminderNotifier(appContext),
                clock = SystemEngineClock(),
                log = logger,
            )
            block(engine)
        }
    }

    /** Runs engine work on the engine thread and tells Flutter (if alive) afterwards. */
    fun submit(context: Context, description: String, block: (ReminderEngine) -> Unit): java.util.concurrent.Future<*> {
        val appContext = context.applicationContext
        return executor.submit {
            try {
                withEngine(appContext, block) ?: Log.i(TAG, "$description skipped: database not created yet")
            } catch (t: Throwable) {
                Log.e(TAG, "$description failed", t)
            } finally {
                FlutterBridge.notifyDataChanged()
            }
        }
    }

    /**
     * For BroadcastReceivers: keeps the receiver (and the wake lock Android
     * holds for it) alive until the work is done.
     */
    fun runFromReceiver(
        receiver: BroadcastReceiver,
        context: Context,
        description: String,
        block: (ReminderEngine) -> Unit,
    ) {
        val pendingResult = receiver.goAsync()
        val appContext = context.applicationContext
        executor.execute {
            try {
                withEngine(appContext, block) ?: Log.i(TAG, "$description skipped: database not created yet")
            } catch (t: Throwable) {
                Log.e(TAG, "$description failed", t)
            } finally {
                FlutterBridge.notifyDataChanged()
                pendingResult.finish()
            }
        }
    }
}
