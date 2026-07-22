import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/domain/services/app_release_notes_service.dart';

final class PersistingGiteeLatestReleaseRepository
    implements GiteeLatestReleaseRepository {
  PersistingGiteeLatestReleaseRepository({
    required GiteeLatestReleaseRepository delegate,
    required AppReleaseNotesService releaseNotesService,
  }) : _delegate = delegate,
       _releaseNotesService = releaseNotesService;

  final GiteeLatestReleaseRepository _delegate;
  final AppReleaseNotesService _releaseNotesService;

  @override
  Future<GiteeReleaseLookupResult> getLatest({
    bool forceRefresh = false,
  }) async {
    final result = await _delegate.getLatest(forceRefresh: forceRefresh);
    if (result case GiteeReleaseLookupSuccess(:final candidate)) {
      await _releaseNotesService.rememberCandidate(candidate);
    }
    return result;
  }
}
