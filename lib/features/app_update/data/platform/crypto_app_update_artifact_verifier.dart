import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_checksum.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_verification_result.dart';
import 'package:y300/features/app_update/domain/services/app_update_artifact_verifier.dart';

final class CryptoAppUpdateArtifactVerifier
    implements AppUpdateArtifactVerifier {
  CryptoAppUpdateArtifactVerifier({this.maxApkBytes = defaultMaxApkBytes});

  static const int defaultMaxApkBytes = 512 * 1024 * 1024;

  final int maxApkBytes;

  @override
  Future<AppUpdateVerificationResult> verify({
    required AppUpdateArtifact artifact,
    required AppUpdateChecksum checksum,
    required String apkPath,
  }) async {
    // The sha256sum line names the APK being hashed, not the .sha256 asset
    // that carried the line.
    if (checksum.fileName != artifact.fileName) {
      return const AppUpdateVerificationFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.checksumFileNameMismatch,
          message: 'The checksum filename does not match the APK filename.',
        ),
      );
    }

    final file = File(apkPath);
    if (!await file.exists()) {
      return const AppUpdateVerificationFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.apkFileMissing,
          message: 'The downloaded APK file is missing.',
        ),
      );
    }

    late final int fileLength;
    try {
      fileLength = await file.length();
    } on FileSystemException {
      return const AppUpdateVerificationFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.apkReadFailed,
          message: 'The downloaded APK file could not be read.',
        ),
      );
    }
    if (fileLength > maxApkBytes) {
      return const AppUpdateVerificationFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.apkSizeExceeded,
          message: 'The downloaded APK is larger than the allowed limit.',
        ),
      );
    }

    try {
      final actualSha256 = (await sha256.bind(file.openRead()).first)
          .toString()
          .toLowerCase();
      if (actualSha256 != checksum.sha256.toLowerCase()) {
        return const AppUpdateVerificationFailure(
          AppUpdateFailure(
            code: AppUpdateFailureCode.apkHashMismatch,
            message: 'The downloaded APK SHA-256 does not match the release.',
          ),
        );
      }
      return AppUpdateVerificationSuccess(actualSha256: actualSha256);
    } on FileSystemException {
      return const AppUpdateVerificationFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.apkReadFailed,
          message: 'The downloaded APK file could not be read.',
        ),
      );
    }
  }
}
