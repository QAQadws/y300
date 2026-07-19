import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

enum AppUpdatePromptSuppression { ignored, reminderInterval }

sealed class AppUpdateCheckResult {
  const AppUpdateCheckResult();
}

final class AppUpdateCheckFailure extends AppUpdateCheckResult {
  const AppUpdateCheckFailure(this.failure);

  final AppUpdateFailure failure;
}

final class AppUpdateCheckUpToDate extends AppUpdateCheckResult {
  const AppUpdateCheckUpToDate({
    required this.installedVersion,
    required this.latestVersion,
  });

  final String installedVersion;
  final Version latestVersion;
}

final class AppUpdateCheckAvailable extends AppUpdateCheckResult {
  const AppUpdateCheckAvailable({
    required this.version,
    required this.suppression,
  });

  final Version version;
  final AppUpdatePromptSuppression? suppression;
}
