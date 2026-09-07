import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/database/database_connection.dart';
import 'core/platform/do_it_platform.dart';
import 'core/utils/time_zone_service.dart';
import 'features/reminders/presentation/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The platform channel is the only bridge to the Kotlin engine. On Android it
  // tells us where the shared database lives and which timezone the device is
  // in, so both runtimes agree on both.
  final platform = DoItPlatform.forCurrentPlatform();
  final databasePath = await resolveDatabasePath(platform);
  final database = AppDatabase(openDatabaseConnection(databasePath));
  final location = await TimeZoneService.initialize(platform);

  runApp(
    ProviderScope(
      overrides: [
        platformProvider.overrideWithValue(platform),
        appDatabaseProvider.overrideWithValue(database),
        timeZoneLocationProvider.overrideWithValue(location),
      ],
      child: const DoItApp(),
    ),
  );
}
