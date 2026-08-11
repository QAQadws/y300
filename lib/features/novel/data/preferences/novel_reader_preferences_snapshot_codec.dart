import 'dart:convert';

import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

final class NovelReaderPreferencesSnapshotCodec {
  const NovelReaderPreferencesSnapshotCodec();

  static const int schemaVersion = 1;
  static const NovelReaderFlowMode _legacyFlowModeFallback =
      NovelReaderFlowMode.vertical;
  static const double minimumFontSize = 14;
  static const double maximumFontSize = 30;
  static const double minimumLineHeight = 1.2;
  static const double maximumLineHeight = 2.4;

  String encode(NovelReaderPreferences preferences) {
    final normalized = normalize(preferences);
    return jsonEncode(<String, Object>{
      'schemaVersion': schemaVersion,
      'fontSize': normalized.fontSize,
      'lineHeight': normalized.lineHeight,
      'flowMode': normalized.flowMode.storageValue,
      'themePreset': normalized.themePreset.storageValue,
      'conversionMode': normalized.conversionMode.storageValue,
      'safeAreaEnabled': normalized.safeAreaEnabled,
    });
  }

  NovelReaderPreferences decode(String? source) {
    final defaults = NovelReaderPreferences.defaults();
    if (source == null || source.trim().isEmpty) {
      return defaults;
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != schemaVersion) {
        return defaults;
      }
      return defaults.copyWith(
        fontSize: _validDouble(
          decoded['fontSize'],
          min: minimumFontSize,
          max: maximumFontSize,
          fallback: defaults.fontSize,
        ),
        lineHeight: _validDouble(
          decoded['lineHeight'],
          min: minimumLineHeight,
          max: maximumLineHeight,
          fallback: defaults.lineHeight,
        ),
        // A persisted schema-1 snapshot predates the new-reader default.
        // Preserve its former implicit vertical mode when this field is
        // absent or unknown instead of silently migrating an existing user.
        flowMode: _flowMode(decoded['flowMode'], _legacyFlowModeFallback),
        themePreset: _themePreset(decoded['themePreset'], defaults.themePreset),
        conversionMode: _conversionMode(
          decoded['conversionMode'],
          defaults.conversionMode,
        ),
        safeAreaEnabled: _validBool(
          decoded['safeAreaEnabled'],
          fallback: defaults.safeAreaEnabled,
        ),
      );
    } on FormatException {
      return defaults;
    }
  }

  NovelReaderPreferences normalize(NovelReaderPreferences preferences) {
    final defaults = NovelReaderPreferences.defaults();
    return defaults.copyWith(
      fontSize: _validDouble(
        preferences.fontSize,
        min: minimumFontSize,
        max: maximumFontSize,
        fallback: defaults.fontSize,
      ),
      lineHeight: _validDouble(
        preferences.lineHeight,
        min: minimumLineHeight,
        max: maximumLineHeight,
        fallback: defaults.lineHeight,
      ),
      flowMode: preferences.flowMode,
      themePreset: preferences.themePreset,
      conversionMode: preferences.conversionMode,
      safeAreaEnabled: preferences.safeAreaEnabled,
    );
  }

  double _validDouble(
    Object? raw, {
    required double min,
    required double max,
    required double fallback,
  }) {
    final value = raw is num ? raw.toDouble() : null;
    if (value == null || !value.isFinite || value < min || value > max) {
      return fallback;
    }
    return value;
  }

  bool _validBool(Object? raw, {required bool fallback}) {
    return raw is bool ? raw : fallback;
  }

  NovelReaderThemePreset _themePreset(
    Object? raw,
    NovelReaderThemePreset fallback,
  ) {
    if (raw is String) {
      for (final value in NovelReaderThemePreset.values) {
        if (value.storageValue == raw) {
          return value;
        }
      }
      if (raw == 'followSystem' || raw == 'follow_system' || raw == 'system') {
        return NovelReaderThemePreset.followApp;
      }
    }
    return fallback;
  }

  NovelReaderFlowMode _flowMode(Object? raw, NovelReaderFlowMode fallback) {
    if (raw is! String) {
      return fallback;
    }
    return NovelReaderFlowModeCodec.fromStorage(raw, fallback: fallback);
  }

  NovelReaderConversionMode _conversionMode(
    Object? raw,
    NovelReaderConversionMode fallback,
  ) {
    if (raw is String) {
      for (final value in NovelReaderConversionMode.values) {
        if (value.storageValue == raw) {
          return value;
        }
      }
    }
    return fallback;
  }
}
