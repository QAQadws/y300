import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/app_update/data/platform/permission_handler_app_update_install_permission.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_install_permission.dart';
import 'package:y300/features/app_update/domain/models/app_update_install_result.dart';
import 'package:y300/features/app_update/domain/services/app_update_file_store.dart';
import 'package:y300/features/app_update/domain/services/app_update_install_permission_gateway.dart';
import 'package:y300/features/app_update/domain/services/app_update_installer.dart';

const String appUpdateApkMimeType = 'application/vnd.android.package-archive';

typedef AppUpdateOpenFile =
    Future<OpenResult> Function(String path, {String? type});

final class OpenFilexAppUpdateInstaller implements AppUpdateInstaller {
  OpenFilexAppUpdateInstaller({
    required AppUpdateFileStore fileStore,
    AppUpdateInstallPermissionGateway? permissionGateway,
    AppUpdateOpenFile? openFile,
  }) : _fileStore = fileStore,
       _permissionGateway =
           permissionGateway ??
           const PermissionHandlerAppUpdateInstallPermission(),
       _openFile = openFile ?? OpenFilex.open;

  final AppUpdateFileStore _fileStore;
  final AppUpdateInstallPermissionGateway _permissionGateway;
  final AppUpdateOpenFile _openFile;

  @override
  Future<AppUpdateInstallResult> install({
    required String apkPath,
    required AppUpdateArtifact artifact,
  }) async {
    try {
      final expectedPath = await _fileStore.verifiedPath(artifact.identity);
      if (!_samePath(apkPath, expectedPath)) {
        return const AppUpdateInstallFailure(
          AppUpdateFailure(
            code: AppUpdateFailureCode.installerLaunchFailed,
            message:
                'The installer rejected a path outside the verified update directory.',
          ),
        );
      }
      final fileType = await FileSystemEntity.type(apkPath, followLinks: false);
      if (fileType != FileSystemEntityType.file) {
        return const AppUpdateInstallFailure(
          AppUpdateFailure(
            code: AppUpdateFailureCode.apkFileMissing,
            message: 'The verified update APK is missing.',
          ),
        );
      }

      final permission = await _permissionGateway.ensureGranted();
      switch (permission) {
        case AppUpdateInstallPermissionStatus.granted:
          break;
        case AppUpdateInstallPermissionStatus.denied:
          return const AppUpdateInstallPermissionRequired(
            permanentlyDenied: false,
          );
        case AppUpdateInstallPermissionStatus.permanentlyDenied:
          return const AppUpdateInstallPermissionRequired(
            permanentlyDenied: true,
          );
        case AppUpdateInstallPermissionStatus.unsupported:
          return const AppUpdateInstallUnavailable();
      }

      final result = await _openFile(apkPath, type: appUpdateApkMimeType);
      return switch (result.type) {
        ResultType.done => const AppUpdateInstallLaunched(),
        ResultType.fileNotFound => const AppUpdateInstallFailure(
          AppUpdateFailure(
            code: AppUpdateFailureCode.apkFileMissing,
            message: 'The verified update APK could not be opened.',
          ),
        ),
        ResultType.noAppToOpen => const AppUpdateInstallUnavailable(),
        ResultType.permissionDenied => const AppUpdateInstallPermissionRequired(
          permanentlyDenied: false,
        ),
        ResultType.error => const AppUpdateInstallFailure(
          AppUpdateFailure(
            code: AppUpdateFailureCode.installerLaunchFailed,
            message: 'The Android installer could not be opened.',
          ),
        ),
      };
    } on MissingPluginException {
      return const AppUpdateInstallUnavailable();
    } on PlatformException {
      return const AppUpdateInstallFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.installerLaunchFailed,
          message: 'The Android installer could not be opened.',
        ),
      );
    } on FileSystemException {
      return const AppUpdateInstallFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.apkReadFailed,
          message: 'The verified update APK could not be inspected.',
        ),
      );
    } on Object {
      return const AppUpdateInstallFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.installerLaunchFailed,
          message: 'The Android installer failed unexpectedly.',
        ),
      );
    }
  }

  bool _samePath(String first, String second) {
    final normalizedFirst = p.normalize(p.absolute(first));
    final normalizedSecond = p.normalize(p.absolute(second));
    return Platform.isWindows
        ? normalizedFirst.toLowerCase() == normalizedSecond.toLowerCase()
        : normalizedFirst == normalizedSecond;
  }
}
