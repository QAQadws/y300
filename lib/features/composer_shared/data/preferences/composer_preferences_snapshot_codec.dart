import 'dart:convert';

import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';

class ComposerPreferencesSnapshotCodec {
  const ComposerPreferencesSnapshotCodec();

  static const int schemaVersion = 1;

  String encode(ComposerPreferences preferences) {
    return jsonEncode(<String, Object>{
      'schemaVersion': schemaVersion,
      'defaultSurface': preferences.defaultSurface.name,
      'newDraftUseSignature': preferences.newDraftUseSignature,
    });
  }

  ComposerPreferences decode(String? raw) {
    final defaults = ComposerPreferences.defaults();
    if (raw == null || raw.trim().isEmpty) {
      return defaults;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != schemaVersion) {
        return defaults;
      }
      return ComposerPreferences(
        defaultSurface: _surface(decoded['defaultSurface']),
        newDraftUseSignature: decoded['newDraftUseSignature'] is bool
            ? decoded['newDraftUseSignature'] as bool
            : defaults.newDraftUseSignature,
      );
    } catch (_) {
      return defaults;
    }
  }

  ComposerSurfacePreference _surface(Object? raw) {
    for (final surface in ComposerSurfacePreference.values) {
      if (surface.name == raw) {
        return surface;
      }
    }
    return ComposerPreferences.defaults().defaultSurface;
  }
}
