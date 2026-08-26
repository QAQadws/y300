import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart' as forum;
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/auth/domain/services/formhash_provider.dart';

/// Compatibility adapter for write flows that still consume `ApiResult`.
/// Formhash acquisition itself has one canonical package implementation.
final class PackageBackedFormhashProvider implements FormhashProvider {
  const PackageBackedFormhashProvider(this._delegate);

  final forum.ForumFormhashProvider _delegate;

  @override
  Future<ApiResult<String>> loadFormhash({bool preferProfile = false}) async {
    final result = await _delegate.loadFormhash(preferProfile: preferProfile);
    return switch (result) {
      forum.ForumFormhashSuccess(:final value) => ApiSuccess<String>(value),
      forum.ForumFormhashError(:final failure) => ApiFailure<String>(
        _toApiError(failure),
      ),
    };
  }

  ApiError _toApiError(forum.ForumTransportFailure failure) => ApiError(
    type: switch (failure.kind) {
      forum.ForumTransportFailureKind.network => ApiErrorType.network,
      forum.ForumTransportFailureKind.timeout => ApiErrorType.timeout,
      forum.ForumTransportFailureKind.unauthorized => ApiErrorType.unauthorized,
      forum.ForumTransportFailureKind.server => ApiErrorType.server,
      forum.ForumTransportFailureKind.parse => ApiErrorType.parse,
      forum.ForumTransportFailureKind.business => ApiErrorType.business,
      forum.ForumTransportFailureKind.cancelled ||
      forum.ForumTransportFailureKind.unknown => ApiErrorType.unknown,
    },
    message: failure.code,
    code: failure.kind == forum.ForumTransportFailureKind.cancelled
        ? 'request_cancelled'
        : failure.code,
    statusCode: failure.statusCode,
  );
}

final formhashProvider = Provider<FormhashProvider>((ref) {
  final client = ref.watch(yamiboForumClientProvider);
  return PackageBackedFormhashProvider(client.formhashProvider);
});
