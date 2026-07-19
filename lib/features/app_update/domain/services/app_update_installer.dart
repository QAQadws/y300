import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_install_result.dart';

abstract interface class AppUpdateInstaller {
  Future<AppUpdateInstallResult> install({
    required String apkPath,
    required AppUpdateArtifact artifact,
  });
}
