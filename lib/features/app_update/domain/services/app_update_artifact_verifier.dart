import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_checksum.dart';
import 'package:y300/features/app_update/domain/models/app_update_verification_result.dart';

abstract interface class AppUpdateArtifactVerifier {
  Future<AppUpdateVerificationResult> verify({
    required AppUpdateArtifact artifact,
    required AppUpdateChecksum checksum,
    required String apkPath,
  });
}
