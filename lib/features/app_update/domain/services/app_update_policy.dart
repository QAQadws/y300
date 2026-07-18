import 'package:y300/features/app_update/domain/models/app_release.dart';
import 'package:y300/features/app_update/domain/models/app_update_decision.dart';
import 'package:y300/features/app_update/domain/models/installed_app_version.dart';

abstract interface class AppUpdatePolicy {
  const AppUpdatePolicy();

  AppUpdateDecision evaluate({
    required InstalledAppVersion installed,
    required AppRelease latest,
  });
}

final class SemanticVersionAppUpdatePolicy implements AppUpdatePolicy {
  const SemanticVersionAppUpdatePolicy();

  @override
  AppUpdateDecision evaluate({
    required InstalledAppVersion installed,
    required AppRelease latest,
  }) {
    final comparison = latest.semanticVersion.compareTo(
      installed.semanticVersion,
    );
    if (comparison > 0) {
      return AppUpdateAvailable(latest);
    }
    return AppUpToDate(localVersionIsNewer: comparison < 0);
  }
}
