import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';
import 'package:y300/features/app_update/domain/models/app_update_binary_event.dart';
import 'package:y300/features/app_update/domain/models/app_update_checksum.dart';
import 'package:y300/features/app_update/domain/models/app_update_checksum_lookup_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_download_state.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_install_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_verification_result.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';
import 'package:y300/features/app_update/domain/repositories/app_update_checksum_repository.dart';
import 'package:y300/features/app_update/domain/services/app_update_artifact_verifier.dart';
import 'package:y300/features/app_update/domain/services/app_update_binary_downloader.dart';
import 'package:y300/features/app_update/domain/services/app_update_download_service.dart';
import 'package:y300/features/app_update/domain/services/app_update_file_store.dart';
import 'package:y300/features/app_update/domain/services/app_update_installer.dart';

void main() {
  test(
    'runs checksum, download, verification and promotion in order',
    () async {
      final log = <String>[];
      final service = _service(log: log);
      addTearDown(service.dispose);

      final result = await service.start(_artifact());

      expect(result, isA<AppUpdateReadyToInstall>());
      expect(service.state, isA<AppUpdateReadyToInstall>());
      expect(log, <String>[
        'checksum',
        'delete',
        'staging',
        'download',
        'verify',
        'verified',
        'promote',
      ]);
    },
  );

  test('does not promote or install a hash-mismatched APK', () async {
    final log = <String>[];
    final service = _service(
      log: log,
      verification: const AppUpdateVerificationFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.apkHashMismatch,
          message: 'mismatch',
        ),
      ),
    );
    addTearDown(service.dispose);

    final result = await service.start(_artifact());

    expect(result, isA<AppUpdateFailed>());
    expect(
      (result as AppUpdateFailed).failure.code,
      AppUpdateFailureCode.apkHashMismatch,
    );
    expect(log, isNot(contains('promote')));
    expect(log, isNot(contains('install')));
  });

  test(
    'joins same artifact and rejects a different artifact while active',
    () async {
      final checksumCompleter = Completer<AppUpdateChecksumLookupResult>();
      final log = <String>[];
      final service = _service(
        log: log,
        checksumFuture: checksumCompleter.future,
      );
      addTearDown(service.dispose);
      final first = service.start(_artifact());
      final sameFuture = service.start(_artifact());
      final different = service.start(_artifact(version: '0.0.3'));

      expect(sameFuture, same(first));
      expect(
        (await different as AppUpdateFailed).failure.code,
        AppUpdateFailureCode.apkDownloadStartFailed,
      );

      checksumCompleter.complete(
        const AppUpdateChecksumLookupSuccess(
          AppUpdateChecksum(
            sha256:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            fileName: 'y300-v0.0.2-android-arm64-v8a-release.apk',
          ),
        ),
      );
      await first;
    },
  );

  test(
    'installer launch leaves the state pending system confirmation',
    () async {
      final log = <String>[];
      final service = _service(log: log);
      addTearDown(service.dispose);

      await service.start(_artifact());
      final result = await service.installReady();

      expect(result, isA<AppUpdateInstalling>());
      expect(service.state, isA<AppUpdateInstalling>());
      expect(log, contains('install'));
    },
  );
}

AppUpdateDownloadService _service({
  required List<String> log,
  AppUpdateChecksumLookupResult? checksumResult,
  Future<AppUpdateChecksumLookupResult>? checksumFuture,
  AppUpdateVerificationResult? verification,
}) {
  return AppUpdateDownloadService(
    checksumRepository: _FakeChecksumRepository(
      log: log,
      result:
          checksumResult ??
          const AppUpdateChecksumLookupSuccess(
            AppUpdateChecksum(
              sha256:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              fileName: 'y300-v0.0.2-android-arm64-v8a-release.apk',
            ),
          ),
      future: checksumFuture,
    ),
    binaryDownloader: _FakeDownloader(log),
    verifier: _FakeVerifier(log, verification),
    fileStore: _FakeFileStore(log),
    installer: _FakeInstaller(log),
  );
}

AppUpdateArtifact _artifact({String version = '0.0.2'}) {
  final uri = Uri.parse(
    'https://gitee.com/QAQadws/y300-releases/releases/download/'
    'v$version/y300-v$version-android-arm64-v8a-release.apk',
  );
  return AppUpdateArtifact.fromCandidate(
    GiteeReleaseCandidate(
      tag: 'v$version',
      version: Version.parse(version),
      apkUri: uri,
      checksumUri: Uri.parse('$uri.sha256'),
      releaseNotes: null,
    ),
  );
}

final class _FakeChecksumRepository implements AppUpdateChecksumRepository {
  _FakeChecksumRepository({
    required this.log,
    required this.result,
    this.future,
  });

  final List<String> log;
  final AppUpdateChecksumLookupResult result;
  final Future<AppUpdateChecksumLookupResult>? future;

  @override
  Future<AppUpdateChecksumLookupResult> fetchChecksum(
    AppUpdateArtifact artifact,
  ) {
    log.add('checksum');
    return future ?? Future.value(result);
  }
}

final class _FakeDownloader implements AppUpdateBinaryDownloader {
  _FakeDownloader(this.log);

  final List<String> log;

  @override
  Stream<AppUpdateBinaryEvent> download(
    AppUpdateArtifact artifact, {
    required String stagingPath,
  }) async* {
    log.add('download');
    yield AppUpdateBinaryEvent.started(artifact.identity);
    yield AppUpdateBinaryEvent.progress(
      identity: artifact.identity,
      receivedBytes: 1,
      totalBytes: 1,
    );
    yield AppUpdateBinaryEvent.completed(
      identity: artifact.identity,
      receivedBytes: 1,
      totalBytes: 1,
    );
  }

  @override
  Future<void> cancel() async {}
}

final class _FakeVerifier implements AppUpdateArtifactVerifier {
  _FakeVerifier(this.log, this.result);

  final List<String> log;
  final AppUpdateVerificationResult? result;

  @override
  Future<AppUpdateVerificationResult> verify({
    required AppUpdateArtifact artifact,
    required AppUpdateChecksum checksum,
    required String apkPath,
  }) async {
    log.add('verify');
    return result ?? const AppUpdateVerificationSuccess(actualSha256: 'a');
  }
}

final class _FakeFileStore implements AppUpdateFileStore {
  _FakeFileStore(this.log);

  final List<String> log;

  @override
  Future<void> deleteArtifact(AppUpdateArtifactIdentity identity) async {
    log.add('delete');
  }

  @override
  Future<bool> exists(String path) async => true;

  @override
  Stream<List<int>> openRead(String path) => Stream<List<int>>.value(<int>[1]);

  @override
  Future<void> promote({
    required String stagingPath,
    required String verifiedPath,
  }) async {
    log.add('promote');
  }

  @override
  Future<String> stagingPath(AppUpdateArtifactIdentity identity) async {
    log.add('staging');
    return '/updates/staging/${identity.stagingFileName}';
  }

  @override
  Future<String> verifiedPath(AppUpdateArtifactIdentity identity) async {
    log.add('verified');
    return '/updates/verified/${identity.fileName}';
  }

  @override
  Future<void> cleanupStaleArtifacts() async {}
}

final class _FakeInstaller implements AppUpdateInstaller {
  _FakeInstaller(this.log);

  final List<String> log;

  @override
  Future<AppUpdateInstallResult> install({
    required String apkPath,
    required AppUpdateArtifact artifact,
  }) async {
    log.add('install');
    return const AppUpdateInstallLaunched();
  }
}
