import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    as forum;
import 'package:y300/core/network/api_result.dart';

class ThreadPostLocation {
  const ThreadPostLocation({
    required this.tid,
    required this.pid,
    required this.page,
    required this.url,
  });

  final String tid;
  final String pid;
  final int page;
  final String url;
}

abstract class ThreadPostLocator {
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  });
}

/// Compatibility projection for existing App routing consumers.
final class PackageThreadPostLocator implements ThreadPostLocator {
  const PackageThreadPostLocator(this._repository);
  final forum.ThreadPostLocatorRepository _repository;

  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) async {
    final result = await _repository.locate(
      forum.ThreadPostLocationQuery(tid: tid, pid: pid),
    );
    return switch (result) {
      forum.DataReadSuccess<
        forum.ThreadPostLocationData,
        forum.ThreadPostLocatorReadCapabilities
      >(
        :final data,
      ) =>
        ApiSuccess(
          ThreadPostLocation(
            tid: data.tid,
            pid: data.pid,
            page: data.page,
            url: data.resolvedUri.toString(),
          ),
        ),
      final forum.DataReadFailure<
        forum.ThreadPostLocationData,
        forum.ThreadPostLocatorReadCapabilities
      >
      failure =>
        ApiFailure(_toApiError(failure)),
    };
  }
}

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
