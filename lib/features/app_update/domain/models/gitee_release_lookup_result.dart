import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';

enum GiteeReleaseLookupSource { network, cache }

sealed class GiteeReleaseLookupResult {
  const GiteeReleaseLookupResult();
}

final class GiteeReleaseLookupSuccess extends GiteeReleaseLookupResult {
  const GiteeReleaseLookupSuccess({
    required this.candidate,
    required this.source,
  });

  final GiteeReleaseCandidate candidate;
  final GiteeReleaseLookupSource source;
}

final class GiteeReleaseLookupFailure extends GiteeReleaseLookupResult {
  const GiteeReleaseLookupFailure({
    required this.failure,
    required this.source,
  });

  final AppUpdateFailure failure;
  final GiteeReleaseLookupSource source;
}
