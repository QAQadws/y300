import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:y300/features/app_update/domain/models/app_update_install_permission.dart';
import 'package:y300/features/app_update/domain/services/app_update_install_permission_gateway.dart';

final class PermissionHandlerAppUpdateInstallPermission
    implements AppUpdateInstallPermissionGateway {
  const PermissionHandlerAppUpdateInstallPermission();

  @override
  Future<AppUpdateInstallPermissionStatus> ensureGranted() async {
    if (!Platform.isAndroid) {
      return AppUpdateInstallPermissionStatus.unsupported;
    }

    final current = await Permission.requestInstallPackages.status;
    if (current.isGranted) {
      return AppUpdateInstallPermissionStatus.granted;
    }
    final status = await Permission.requestInstallPackages.request();
    if (status.isGranted) {
      return AppUpdateInstallPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied) {
      return AppUpdateInstallPermissionStatus.permanentlyDenied;
    }
    return AppUpdateInstallPermissionStatus.denied;
  }

  @override
  Future<bool> openSettings() {
    return Platform.isAndroid ? openAppSettings() : Future<bool>.value(false);
  }
}
