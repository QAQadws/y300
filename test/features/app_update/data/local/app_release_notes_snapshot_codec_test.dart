import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/data/local/app_release_notes_snapshot_codec.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes.dart';

void main() {
  test('round-trips versioned notes, attempts, and empty bodies', () {
    final snapshot = AppReleaseNotesSnapshot(
      notesByVersion: <String, AppReleaseNotes>{
        '0.0.6': AppReleaseNotes(
          version: Version.parse('0.0.6'),
          tag: 'v0.0.6',
          body: '',
          fetchedAt: DateTime.utc(2026, 7, 22, 1),
        ),
        '0.0.7': AppReleaseNotes(
          version: Version.parse('0.0.7'),
          tag: 'v0.0.7',
          body: 'Release notes',
          fetchedAt: DateTime.utc(2026, 7, 22, 2),
        ),
      },
      attemptsByVersion: <String, DateTime>{
        '0.0.6': DateTime.utc(2026, 7, 22, 3),
      },
    );

    final decoded = AppReleaseNotesSnapshotCodec.decode(
      AppReleaseNotesSnapshotCodec.encode(snapshot),
    );

    expect(decoded.notesByVersion['0.0.6']?.body, isEmpty);
    expect(decoded.notesByVersion['0.0.7']?.body, 'Release notes');
    expect(decoded.attemptsByVersion['0.0.6'], DateTime.utc(2026, 7, 22, 3));
  });

  test('falls back safely for damaged or unsupported snapshots', () {
    expect(
      AppReleaseNotesSnapshotCodec.decode('{invalid').notesByVersion,
      isEmpty,
    );
    expect(
      AppReleaseNotesSnapshotCodec.decode(
        jsonEncode(<String, Object>{'schemaVersion': 99}),
      ).notesByVersion,
      isEmpty,
    );
  });

  test('ignores unknown and invalid entries', () {
    final decoded = AppReleaseNotesSnapshotCodec.decode(
      jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'unknown': true,
        'notes': <Object>[
          <String, Object>{
            'version': '0.0.6',
            'tag': 'v0.0.5',
            'body': 'wrong tag',
            'fetchedAt': '2026-07-22T00:00:00Z',
          },
          <String, Object>{
            'version': '0.0.6',
            'tag': 'v0.0.6',
            'body': 'valid',
            'fetchedAt': '2026-07-22T01:00:00Z',
          },
        ],
      }),
    );

    expect(decoded.notesByVersion, hasLength(1));
    expect(decoded.notesByVersion['0.0.6']?.body, 'valid');
  });

  test('retains only the eight newest notes and attempts', () {
    final snapshot = AppReleaseNotesSnapshot();
    for (var index = 0; index < 10; index++) {
      final version = Version(0, 0, index + 1);
      final timestamp = DateTime.utc(2026, 7, 22, index);
      snapshot.notesByVersion[version.toString()] = AppReleaseNotes(
        version: version,
        tag: 'v$version',
        body: '$index',
        fetchedAt: timestamp,
      );
      snapshot.attemptsByVersion[version.toString()] = timestamp;
    }

    final decoded = AppReleaseNotesSnapshotCodec.decode(
      AppReleaseNotesSnapshotCodec.encode(snapshot),
    );

    expect(decoded.notesByVersion, hasLength(8));
    expect(decoded.attemptsByVersion, hasLength(8));
    expect(decoded.notesByVersion, isNot(contains('0.0.1')));
    expect(decoded.notesByVersion, isNot(contains('0.0.2')));
    expect(decoded.notesByVersion, contains('0.0.10'));
  });
}
