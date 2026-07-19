import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

sealed class AppUpdateLaunchResult {
  const AppUpdateLaunchResult();
}

final class AppUpdateLaunchSuccess extends AppUpdateLaunchResult {
  const AppUpdateLaunchSuccess();
}

final class AppUpdateLaunchFailure extends AppUpdateLaunchResult {
  const AppUpdateLaunchFailure(this.failure);

  final AppUpdateFailure failure;
}
