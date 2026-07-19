import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/app_update/data/gitee/gitee_release_parser.dart';
import 'package:y300/features/app_update/data/local/local_app_update_file_store.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';

import '../../test_support/gitee_release_phase0_fixture.dart';

void main() {
  late Directory supportDirectory;
  late AppUpdateArtifactIdentity identity;
  late LocalAppUpdateFileStore store;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'y300-update-file-store-',
    );
    identity = (await _fixtureArtifact()).identity;
    store = LocalAppUpdateFileStore(
      applicationSupportDirectoryProvider: () async => supportDirectory,
      now: () => DateTime(2026, 7, 19),
      staleArtifactAge: const Duration(days: 7),
    );
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test(
    'uses protected staging and verified directories with canonical names',
    () async {
      final stagingPath = await store.stagingPath(identity);
      final verifiedPath = await store.verifiedPath(identity);

      expect(
        stagingPath,
        endsWith(
          'updates${Platform.pathSeparator}staging${Platform.pathSeparator}${identity.fileName}.part',
        ),
      );
      expect(
        verifiedPath,
        endsWith(
          'updates${Platform.pathSeparator}verified${Platform.pathSeparator}${identity.fileName}',
        ),
      );
      expect(stagingPath, isNot(contains('application/zip')));
    },
  );

  test('promotes a complete staging file and removes the .part path', () async {
    final stagingPath = await store.stagingPath(identity);
    final verifiedPath = await store.verifiedPath(identity);
    await File(stagingPath).writeAsBytes(<int>[1, 2, 3], flush: true);

    await store.promote(stagingPath: stagingPath, verifiedPath: verifiedPath);

    expect(await File(stagingPath).exists(), isFalse);
    expect(await File(verifiedPath).readAsBytes(), <int>[1, 2, 3]);
  });

  test('rejects paths outside the managed update root', () async {
    final outside = File('${supportDirectory.parent.path}/outside.apk');

    await expectLater(store.exists(outside.path), throwsArgumentError);
    await expectLater(
      store.promote(stagingPath: outside.path, verifiedPath: outside.path),
      throwsArgumentError,
    );
  });

  test(
    'cleans stale staging files but does not remove verified files',
    () async {
      final stagingPath = await store.stagingPath(identity);
      final verifiedPath = await store.verifiedPath(identity);
      final recentPath = '${File(stagingPath).parent.path}/recent.apk.part';
      await File(stagingPath).writeAsBytes(<int>[1]);
      await File(recentPath).writeAsBytes(<int>[2]);
      await File(verifiedPath).writeAsBytes(<int>[3]);
      await File(stagingPath).setLastModified(DateTime(2026, 7, 1));

      await store.cleanupStaleArtifacts();

      expect(await File(stagingPath).exists(), isFalse);
      expect(await File(recentPath).exists(), isTrue);
      expect(await File(verifiedPath).exists(), isTrue);
    },
  );
}

Future<AppUpdateArtifact> _fixtureArtifact() async {
  final parsed = GiteeReleaseParser().parse(
    await loadGiteeLatestReleaseV001Fixture(),
  );
  return AppUpdateArtifact.fromCandidate(
    (parsed as GiteeReleaseParseSuccess).candidate,
  );
}
