import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_filex/open_filex.dart';
import 'package:y300/features/app_update/data/gitee/gitee_release_parser.dart';
import 'package:y300/features/app_update/data/local/local_app_update_file_store.dart';
import 'package:y300/features/app_update/data/platform/open_filex_app_update_installer.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_install_permission.dart';
import 'package:y300/features/app_update/domain/models/app_update_install_result.dart';
import 'package:y300/features/app_update/domain/services/app_update_install_permission_gateway.dart';

import '../../test_support/gitee_release_phase0_fixture.dart';

void main() {
  late Directory supportDirectory;
  late AppUpdateArtifact artifact;
  late LocalAppUpdateFileStore fileStore;
  late String verifiedPath;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'y300-update-installer-',
    );
    artifact = await _fixtureArtifact();
    fileStore = LocalAppUpdateFileStore(
      applicationSupportDirectoryProvider: () async => supportDirectory,
    );
    verifiedPath = await fileStore.verifiedPath(artifact.identity);
    await File(verifiedPath).writeAsBytes(<int>[1, 2, 3], flush: true);
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test(
    'opens only the verified APK with the Android package MIME type',
    () async {
      final permission = _FakePermissionGateway(
        AppUpdateInstallPermissionStatus.granted,
      );
      String? openedPath;
      String? openedType;
      final installer = OpenFilexAppUpdateInstaller(
        fileStore: fileStore,
        permissionGateway: permission,
        openFile: (path, {type}) async {
          openedPath = path;
          openedType = type;
          return OpenResult(type: ResultType.done);
        },
      );

      final result = await installer.install(
        apkPath: verifiedPath,
        artifact: artifact,
      );

      expect(result, isA<AppUpdateInstallLaunched>());
      expect(openedPath, verifiedPath);
      expect(openedType, appUpdateApkMimeType);
      expect(permission.ensureCalls, 1);
    },
  );

  test('rejects an APK path outside the artifact verified location', () async {
    final permission = _FakePermissionGateway(
      AppUpdateInstallPermissionStatus.granted,
    );
    var openCalls = 0;
    final installer = OpenFilexAppUpdateInstaller(
      fileStore: fileStore,
      permissionGateway: permission,
      openFile: (path, {type}) async {
        openCalls += 1;
        return OpenResult(type: ResultType.done);
      },
    );
    final outside = File('${supportDirectory.path}/outside.apk');
    await outside.writeAsBytes(<int>[1]);

    final result = await installer.install(
      apkPath: outside.path,
      artifact: artifact,
    );

    expect(_failureCode(result), AppUpdateFailureCode.installerLaunchFailed);
    expect(permission.ensureCalls, 0);
    expect(openCalls, 0);
  });

  test(
    'reports a missing verified APK without requesting permission',
    () async {
      await File(verifiedPath).delete();
      final permission = _FakePermissionGateway(
        AppUpdateInstallPermissionStatus.granted,
      );
      final installer = OpenFilexAppUpdateInstaller(
        fileStore: fileStore,
        permissionGateway: permission,
      );

      final result = await installer.install(
        apkPath: verifiedPath,
        artifact: artifact,
      );

      expect(_failureCode(result), AppUpdateFailureCode.apkFileMissing);
      expect(permission.ensureCalls, 0);
    },
  );

  test('keeps denied and permanently denied permission actionable', () async {
    for (final entry in <(AppUpdateInstallPermissionStatus, bool)>[
      (AppUpdateInstallPermissionStatus.denied, false),
      (AppUpdateInstallPermissionStatus.permanentlyDenied, true),
    ]) {
      final installer = OpenFilexAppUpdateInstaller(
        fileStore: fileStore,
        permissionGateway: _FakePermissionGateway(entry.$1),
        openFile: (path, {type}) async {
          fail('The installer must not open before permission is granted.');
        },
      );

      final result = await installer.install(
        apkPath: verifiedPath,
        artifact: artifact,
      );

      expect(result, isA<AppUpdateInstallPermissionRequired>());
      expect(
        (result as AppUpdateInstallPermissionRequired).permanentlyDenied,
        entry.$2,
      );
    }
  });

  test(
    'maps unavailable and failed installer results without claiming success',
    () async {
      for (final entry in <(ResultType, Type, AppUpdateFailureCode?)>[
        (ResultType.noAppToOpen, AppUpdateInstallUnavailable, null),
        (
          ResultType.fileNotFound,
          AppUpdateInstallFailure,
          AppUpdateFailureCode.apkFileMissing,
        ),
        (
          ResultType.error,
          AppUpdateInstallFailure,
          AppUpdateFailureCode.installerLaunchFailed,
        ),
      ]) {
        final installer = OpenFilexAppUpdateInstaller(
          fileStore: fileStore,
          permissionGateway: _FakePermissionGateway(
            AppUpdateInstallPermissionStatus.granted,
          ),
          openFile: (path, {type}) async => OpenResult(type: entry.$1),
        );

        final result = await installer.install(
          apkPath: verifiedPath,
          artifact: artifact,
        );

        expect(result.runtimeType, entry.$2);
        if (entry.$3 != null) {
          expect(_failureCode(result), entry.$3);
        }
      }
    },
  );

  test(
    'contains platform channel failures at the installer boundary',
    () async {
      final installer = OpenFilexAppUpdateInstaller(
        fileStore: fileStore,
        permissionGateway: _FakePermissionGateway(
          AppUpdateInstallPermissionStatus.granted,
        ),
        openFile: (path, {type}) {
          throw PlatformException(code: 'installer_failed');
        },
      );

      final result = await installer.install(
        apkPath: verifiedPath,
        artifact: artifact,
      );

      expect(_failureCode(result), AppUpdateFailureCode.installerLaunchFailed);
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

AppUpdateFailureCode _failureCode(AppUpdateInstallResult result) {
  expect(result, isA<AppUpdateInstallFailure>());
  return (result as AppUpdateInstallFailure).failure.code;
}

final class _FakePermissionGateway
    implements AppUpdateInstallPermissionGateway {
  _FakePermissionGateway(this.status);

  final AppUpdateInstallPermissionStatus status;
  int ensureCalls = 0;

  @override
  Future<AppUpdateInstallPermissionStatus> ensureGranted() async {
    ensureCalls += 1;
    return status;
  }

  @override
  Future<bool> openSettings() async => true;
}
