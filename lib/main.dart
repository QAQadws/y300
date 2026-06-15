import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/y300_app.dart';
import 'package:y300/features/library_shared/data/sync_diagnostic_providers.dart';
import 'package:y300/features/library_shared/data/sync_diagnostic_settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SharedPrefsSyncDiagnosticSettingsRepository();
  final manualModeEnabled = await settings.loadManualModeEnabled();
  runApp(
    ProviderScope(
      overrides: [
        syncDiagnosticInitialManualModeProvider.overrideWithValue(
          manualModeEnabled,
        ),
      ],
      child: const Y300App(),
    ),
  );
}
