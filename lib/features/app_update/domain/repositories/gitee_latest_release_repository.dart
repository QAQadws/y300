import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';

abstract interface class GiteeLatestReleaseRepository {
  Future<GiteeReleaseLookupResult> getLatest({bool forceRefresh = false});
}
