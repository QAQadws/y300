import 'package:y300/features/app_update/domain/models/app_release.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

sealed class AppUpdateDecision {
  const AppUpdateDecision();
}

final class AppUpdateAvailable extends AppUpdateDecision {
  const AppUpdateAvailable(this.release);

  final AppRelease release;
}

final class AppUpToDate extends AppUpdateDecision {
  const AppUpToDate({required this.localVersionIsNewer});

  final bool localVersionIsNewer;
}

final class AppUpdateCheckFailed extends AppUpdateDecision {
  const AppUpdateCheckFailed(this.failure);

  final AppUpdateFailure failure;
}
