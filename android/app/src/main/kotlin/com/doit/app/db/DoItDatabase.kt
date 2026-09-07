package com.doit.app.db

import android.content.Context
import java.io.File

/**
 * Location of the SQLite file shared with Flutter (Drift).
 *
 * The Dart side asks for this path over the platform channel before opening
 * its connection, so there is exactly one definition of where the data lives.
 */
object DoItDatabase {
    const val FILE_NAME = "do_it.sqlite"

    fun file(context: Context): File = File(context.applicationContext.filesDir, FILE_NAME)
}
