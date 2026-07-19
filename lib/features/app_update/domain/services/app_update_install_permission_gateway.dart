import 'package:y300/features/app_update/domain/models/app_update_install_permission.dart';

abstract interface class AppUpdateInstallPermissionGateway {
  Future<AppUpdateInstallPermissionStatus> ensureGranted();

  Future<bool> openSettings();
}
