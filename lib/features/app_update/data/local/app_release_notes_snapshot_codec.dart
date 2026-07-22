import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes.dart';
import 'package:y300/features/app_update/domain/services/app_version_codec.dart';

final class AppReleaseNotesSnapshot {
  AppReleaseNotesSnapshot({
    Map<String, AppReleaseNotes>? notesByVersion,
    Map<String, DateTime>? attemptsByVersion,
  }) : notesByVersion = notesByVersion ?? <String, AppReleaseNotes>{},
       attemptsByVersion = attemptsByVersion ?? <String, DateTime>{};

  final Map<String, AppReleaseNotes> notesByVersion;
  final Map<String, DateTime> attemptsByVersion;
}

abstract final class AppReleaseNotesSnapshotCodec {
  static const int schemaVersion = 1;
  static const int maxEntries = 8;
  static const int maxBodyCharacters = 8192;
  static const AppVersionCodec _versionCodec = AppVersionCodec();

  static AppReleaseNotesSnapshot decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return AppReleaseNotesSnapshot();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != schemaVersion) {
        return AppReleaseNotesSnapshot();
      }
      final snapshot = AppReleaseNotesSnapshot();
      final notes = decoded['notes'];
      if (notes is List) {
        for (final value in notes) {
          final entry = _decodeNotes(value);
          if (entry != null) {
            snapshot.notesByVersion[entry.version.toString()] = entry;
          }
        }
      }
      final attempts = decoded['attempts'];
      if (attempts is List) {
        for (final value in attempts) {
          final entry = _decodeAttempt(value);
          if (entry != null) {
            snapshot.attemptsByVersion[entry.$1] = entry.$2;
          }
        }
      }
      _prune(snapshot);
      return snapshot;
    } on Object {
      return AppReleaseNotesSnapshot();
    }
  }

  static String encode(AppReleaseNotesSnapshot snapshot) {
    _prune(snapshot);
    final notes = snapshot.notesByVersion.values.toList()
      ..sort((a, b) => b.fetchedAt.compareTo(a.fetchedAt));
    final attempts = snapshot.attemptsByVersion.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return jsonEncode(<String, Object>{
      'schemaVersion': schemaVersion,
      'notes': <Map<String, String>>[
        for (final notes in notes)
          <String, String>{
            'version': notes.version.toString(),
            'tag': notes.tag,
            'body': notes.body,
            'fetchedAt': notes.fetchedAt.toUtc().toIso8601String(),
          },
      ],
      'attempts': <Map<String, String>>[
        for (final attempt in attempts)
          <String, String>{
            'version': attempt.key,
            'attemptedAt': attempt.value.toUtc().toIso8601String(),
          },
      ],
    });
  }

  static AppReleaseNotes? _decodeNotes(Object? value) {
    if (value is! Map) {
      return null;
    }
    final versionValue = value['version'];
    final tag = value['tag'];
    final body = value['body'];
    final fetchedAtValue = value['fetchedAt'];
    if (versionValue is! String ||
        tag is! String ||
        body is! String ||
        fetchedAtValue is! String ||
        body.characters.length > maxBodyCharacters) {
      return null;
    }
    final version = _versionCodec.parseVersionName(versionValue);
    final fetchedAt = DateTime.tryParse(fetchedAtValue);
    if (version == null ||
        fetchedAt == null ||
        tag != _versionCodec.canonicalTag(version)) {
      return null;
    }
    return AppReleaseNotes(
      version: version,
      tag: tag,
      body: body,
      fetchedAt: fetchedAt.toUtc(),
    );
  }

  static (String, DateTime)? _decodeAttempt(Object? value) {
    if (value is! Map) {
      return null;
    }
    final versionValue = value['version'];
    final attemptedAtValue = value['attemptedAt'];
    if (versionValue is! String || attemptedAtValue is! String) {
      return null;
    }
    final version = _versionCodec.parseVersionName(versionValue);
    final attemptedAt = DateTime.tryParse(attemptedAtValue);
    if (version == null || attemptedAt == null) {
      return null;
    }
    return (version.toString(), attemptedAt.toUtc());
  }

  static void _prune(AppReleaseNotesSnapshot snapshot) {
    _pruneMap(snapshot.notesByVersion, timestamp: (notes) => notes.fetchedAt);
    _pruneMap(snapshot.attemptsByVersion, timestamp: (attempt) => attempt);
  }

  static void _pruneMap<T>(
    Map<String, T> entries, {
    required DateTime Function(T value) timestamp,
  }) {
    if (entries.length <= maxEntries) {
      return;
    }
    final sorted = entries.entries.toList()
      ..sort((a, b) => timestamp(b.value).compareTo(timestamp(a.value)));
    final retained = sorted.take(maxEntries).map((entry) => entry.key).toSet();
    entries.removeWhere((key, _) => !retained.contains(key));
  }
}
