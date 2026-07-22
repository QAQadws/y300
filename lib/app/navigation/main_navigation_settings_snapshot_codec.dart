import 'dart:convert';

import 'package:y300/app/navigation/main_navigation_settings.dart';

abstract final class MainNavigationSettingsSnapshotCodec {
  static const int schemaVersion = 1;

  static String encode(MainNavigationSettings settings) {
    return jsonEncode(<String, Object?>{
      'schemaVersion': schemaVersion,
      'order': settings.managedOrder
          .map((destination) => destination.name)
          .toList(growable: false),
      'hidden': settings.hiddenDestinations
          .map((destination) => destination.name)
          .toList(growable: false),
    });
  }

  static MainNavigationSettings decode(String? raw) {
    final normalized = raw?.trim();
    if (normalized == null || normalized.isEmpty) {
      return MainNavigationSettings.defaults();
    }
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is! Map || decoded['schemaVersion'] != schemaVersion) {
        return MainNavigationSettings.defaults();
      }
      return MainNavigationSettings(
        managedOrder: _decodeDestinations(decoded['order']),
        hiddenDestinations: _decodeDestinations(decoded['hidden']),
      );
    } on Object {
      return MainNavigationSettings.defaults();
    }
  }

  static Iterable<MainShellDestination> _decodeDestinations(Object? raw) sync* {
    if (raw is! List) {
      return;
    }
    for (final value in raw.whereType<String>()) {
      for (final destination in MainShellDestination.values) {
        if (destination.name == value && destination.isManaged) {
          yield destination;
          break;
        }
      }
    }
  }
}
