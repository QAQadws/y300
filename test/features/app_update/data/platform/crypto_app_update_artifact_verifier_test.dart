import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/app_update/data/gitee/gitee_release_parser.dart';
import 'package:y300/features/app_update/data/platform/crypto_app_update_artifact_verifier.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_checksum.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_verification_result.dart';

import '../../test_support/gitee_release_phase0_fixture.dart';

void main() {
  late Directory directory;
  late AppUpdateArtifact artifact;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'y300-app-update-verifier-',
    );
    final parsed = GiteeReleaseParser().parse(
      await loadGiteeLatestReleaseV001Fixture(),
    );
    artifact = AppUpdateArtifact.fromCandidate(
      (parsed as GiteeReleaseParseSuccess).candidate,
    );
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('streams the APK and accepts a matching SHA-256', () async {
    final bytes = List<int>.generate(4096, (index) => index % 251);
    final path = await _write(directory, 'update.apk', bytes);
    final result = await CryptoAppUpdateArtifactVerifier().verify(
      artifact: artifact,
      checksum: AppUpdateChecksum(
        sha256: sha256.convert(bytes).toString(),
        fileName: artifact.checksumFileName,
      ),
      apkPath: path,
    );

    expect(result, isA<AppUpdateVerificationSuccess>());
  });

  test('rejects a hash mismatch before installation can proceed', () async {
    final path = await _write(directory, 'update.apk', <int>[1, 2, 3]);
    final result = await CryptoAppUpdateArtifactVerifier().verify(
      artifact: artifact,
      checksum: AppUpdateChecksum(
        sha256: _zeroHash,
        fileName: artifact.checksumFileName,
      ),
      apkPath: path,
    );

    expect(
      (result as AppUpdateVerificationFailure).failure.code,
      AppUpdateFailureCode.apkHashMismatch,
    );
  });

  test('rejects a missing file and an oversized file', () async {
    final missing = await CryptoAppUpdateArtifactVerifier().verify(
      artifact: artifact,
      checksum: const AppUpdateChecksum(
        sha256: _zeroHash,
        fileName: 'y300-v0.0.1-android-arm64-v8a-release.apk.sha256',
      ),
      apkPath: '${directory.path}${Platform.pathSeparator}missing.apk',
    );
    final path = await _write(directory, 'large.apk', <int>[1, 2, 3, 4]);
    final oversized = await CryptoAppUpdateArtifactVerifier(maxApkBytes: 3)
        .verify(
          artifact: artifact,
          checksum: const AppUpdateChecksum(
            sha256: _zeroHash,
            fileName: 'y300-v0.0.1-android-arm64-v8a-release.apk.sha256',
          ),
          apkPath: path,
        );

    expect(
      (missing as AppUpdateVerificationFailure).failure.code,
      AppUpdateFailureCode.apkFileMissing,
    );
    expect(
      (oversized as AppUpdateVerificationFailure).failure.code,
      AppUpdateFailureCode.apkSizeExceeded,
    );
  });

  test(
    'rejects a checksum filename that belongs to another artifact',
    () async {
      final path = await _write(directory, 'update.apk', <int>[1, 2, 3]);
      final result = await CryptoAppUpdateArtifactVerifier().verify(
        artifact: artifact,
        checksum: const AppUpdateChecksum(
          sha256: _zeroHash,
          fileName: 'other.apk.sha256',
        ),
        apkPath: path,
      );

      expect(
        (result as AppUpdateVerificationFailure).failure.code,
        AppUpdateFailureCode.checksumFileNameMismatch,
      );
    },
  );
}

const String _zeroHash =
    '0000000000000000000000000000000000000000000000000000000000000000';

Future<String> _write(Directory directory, String name, List<int> bytes) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
