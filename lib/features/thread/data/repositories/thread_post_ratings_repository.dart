import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    as forum;
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';

final class ThreadPostRatingDetails {
  const ThreadPostRatingDetails({
    required this.participantCount,
    required this.totalScoreText,
    required this.ratings,
  });

  final int participantCount;
  final String totalScoreText;
  final List<forum.ThreadPostRating> ratings;
}

abstract interface class ThreadPostRatingsRepository {
  Future<ApiResult<ThreadPostRatingDetails>> loadAll(String viewAllUrl);
}

/// Compatibility projection for the existing thread-detail controller.
final class PackageThreadPostRatingsRepository
    implements ThreadPostRatingsRepository {
  const PackageThreadPostRatingsRepository({required this.repository});

  final forum.ThreadPostRatingsRepository repository;

  @override
  Future<ApiResult<ThreadPostRatingDetails>> loadAll(String viewAllUrl) async {
    final uri = Uri.tryParse(viewAllUrl.trim());
    final tid = uri?.queryParameters['tid']?.trim() ?? '';
    final pid = uri?.queryParameters['pid']?.trim() ?? '';
    final result = await repository.load(
      forum.ThreadPostRatingsQuery(tid: tid, pid: pid),
    );
    return switch (result) {
      forum.DataReadSuccess<
        forum.ThreadPostRatingsData,
        forum.ThreadPostRatingsReadCapabilities
      >(
        :final data,
      ) =>
        ApiSuccess(
          ThreadPostRatingDetails(
            participantCount: data.participantCount,
            totalScoreText: data.totalScoreText,
            ratings: data.ratings,
          ),
        ),
      final forum.DataReadFailure<
        forum.ThreadPostRatingsData,
        forum.ThreadPostRatingsReadCapabilities
      >
      failure =>
        ApiFailure(_toApiError(failure)),
    };
  }
}

final threadPostRatingsRepositoryProvider =
    Provider<ThreadPostRatingsRepository>(
      (ref) => PackageThreadPostRatingsRepository(
        repository: ref.watch(yamiboForumClientProvider).postRatings!,
      ),
    );

ApiError _toApiError<T, C>(forum.DataReadFailure<T, C> failure) => ApiError(
  type: switch (failure.kind) {
    forum.DataReadFailureKind.network ||
    forum.DataReadFailureKind.cancelled => ApiErrorType.network,
    forum.DataReadFailureKind.timeout => ApiErrorType.timeout,
    forum.DataReadFailureKind.unauthorized => ApiErrorType.unauthorized,
    forum.DataReadFailureKind.server => ApiErrorType.server,
    forum.DataReadFailureKind.parse => ApiErrorType.parse,
    forum.DataReadFailureKind.business ||
    forum.DataReadFailureKind.unsupported => ApiErrorType.business,
    forum.DataReadFailureKind.unknown => ApiErrorType.unknown,
  },
  message: failure.diagnosticMessage,
  code: failure.code,
  statusCode: failure.statusCode,
);
