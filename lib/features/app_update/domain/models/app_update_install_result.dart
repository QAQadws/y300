import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

sealed class AppUpdateInstallResult {
  const AppUpdateInstallResult();
}

final class AppUpdateInstallLaunched extends AppUpdateInstallResult {
  const AppUpdateInstallLaunched();
}

final class AppUpdateInstallPermissionRequired extends AppUpdateInstallResult {
  const AppUpdateInstallPermissionRequired({required this.permanentlyDenied});

  final bool permanentlyDenied;
}

final class AppUpdateInstallUnavailable extends AppUpdateInstallResult {
  const AppUpdateInstallUnavailable();
}

final class AppUpdateInstallFailure extends AppUpdateInstallResult {
  const AppUpdateInstallFailure(this.failure);

  final AppUpdateFailure failure;
}
