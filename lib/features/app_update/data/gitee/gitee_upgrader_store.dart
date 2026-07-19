import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';

typedef AppUpdateFailureReporter = void Function(AppUpdateFailure failure);

final class GiteeUpgraderStore extends UpgraderStore {
  GiteeUpgraderStore({
    required GiteeLatestReleaseRepository repository,
    AppUpdateFailureReporter? onFailure,
  }) : _repository = repository,
       _onFailure = onFailure;

  final GiteeLatestReleaseRepository _repository;
  final AppUpdateFailureReporter? _onFailure;

  @override
  Future<UpgraderVersionInfo> getVersionInfo({
    required UpgraderState state,
    required Version installedVersion,
    required String? country,
    required String? language,
  }) async {
    try {
      final result = await _repository.getLatest();
      return switch (result) {
        GiteeReleaseLookupSuccess(:final candidate) => UpgraderVersionInfo(
          appStoreListingURL: candidate.apkUri.toString(),
          appStoreVersion: candidate.version,
          installedVersion: installedVersion,
          releaseNotes: candidate.releaseNotes,
        ),
        GiteeReleaseLookupFailure(:final failure, :final source) =>
          _emptyVersionInfo(
            installedVersion,
            failure,
            reportFailure: source == GiteeReleaseLookupSource.network,
          ),
      };
    } on Object {
      return _emptyVersionInfo(
        installedVersion,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.remoteUnavailable,
          message: 'Gitee update store failed unexpectedly.',
        ),
      );
    }
  }

  UpgraderVersionInfo _emptyVersionInfo(
    Version installedVersion,
    AppUpdateFailure failure, {
    bool reportFailure = true,
  }) {
    if (reportFailure) {
      _onFailure?.call(failure);
    }
    return UpgraderVersionInfo(installedVersion: installedVersion);
  }
}
