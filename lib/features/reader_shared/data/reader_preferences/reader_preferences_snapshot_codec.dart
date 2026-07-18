import 'dart:convert';

import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';

final class ReaderPreferencesSnapshotCodec {
  const ReaderPreferencesSnapshotCodec();

  static const int schemaVersion = 1;

  String encode(ReaderPreferences preferences) {
    final normalized = normalize(
      readerMode: preferences.readerMode.name,
      pageFit: preferences.pageFit.name,
      background: preferences.background.name,
      pageSpacing: preferences.pageSpacing,
      showPageIndicator: preferences.showPageIndicator,
    );
    return jsonEncode(<String, Object>{
      'schemaVersion': schemaVersion,
      'readerMode': normalized.readerMode.name,
      'pageFit': normalized.pageFit.name,
      'background': normalized.background.name,
      'pageSpacing': normalized.pageSpacing,
      'showPageIndicator': normalized.showPageIndicator,
    });
  }

  ReaderPreferences decode(String? source) {
    if (source == null || source.trim().isEmpty) {
      return ReaderPreferences.defaults();
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != schemaVersion) {
        return ReaderPreferences.defaults();
      }
      return normalize(
        readerMode: decoded['readerMode'],
        pageFit: decoded['pageFit'],
        background: decoded['background'],
        pageSpacing: decoded['pageSpacing'],
        showPageIndicator: decoded['showPageIndicator'],
      );
    } on FormatException {
      return ReaderPreferences.defaults();
    }
  }

  ReaderPreferences normalize({
    Object? readerMode,
    Object? pageFit,
    Object? background,
    Object? pageSpacing,
    Object? showPageIndicator,
  }) {
    final defaults = ReaderPreferences.defaults();
    final spacing = pageSpacing is num && pageSpacing.isFinite
        ? pageSpacing.toDouble()
        : defaults.pageSpacing;
    return ReaderPreferences(
      readerMode: _enumByName(
        readerMode,
        ReaderModePreference.values,
        defaults.readerMode,
      ),
      pageFit: _enumByName(
        pageFit,
        ReaderPageFitPreference.values,
        defaults.pageFit,
      ),
      background: _enumByName(
        background,
        ReaderBackgroundPreference.values,
        defaults.background,
      ),
      pageSpacing: spacing.clamp(0.0, 48.0).toDouble(),
      showPageIndicator: showPageIndicator is bool
          ? showPageIndicator
          : defaults.showPageIndicator,
    );
  }

  T _enumByName<T extends Enum>(Object? raw, List<T> values, T fallback) {
    if (raw is String) {
      for (final value in values) {
        if (value.name == raw) {
          return value;
        }
      }
    }
    return fallback;
  }
}
