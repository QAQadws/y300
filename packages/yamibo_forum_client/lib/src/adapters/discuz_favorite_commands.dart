import '../contracts/cache_load_policy.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/favorite_commands.dart';
import '../contracts/favorite_directories.dart';
import '../network/forum_request.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_formhash_provider.dart';
import 'discuz_api_client.dart';

/// Experimental Discuz v4 command for forum favorite target states.
final class DiscuzFavoriteForumCommandAdapter implements FavoriteForumCommand {
  /// Creates the command around the shared API, formhash, and directory ports.
  const DiscuzFavoriteForumCommandAdapter(
    this._api,
    this._formhash,
    this._directory,
  );

  final DiscuzApiClient _api;
  final ForumFormhashProvider _formhash;
  final FavoriteForumDirectoryRepository _directory;

  @override
  FavoriteMutationCapabilities get capabilities =>
      _favoriteMutationCapabilities;

  @override
  Future<DataCommandResult<ForumFavoriteReceipt>> execute(
    SetForumFavoriteRequest request,
  ) async {
    final fid = request.fid.trim();
    if (!_isPositiveIdentity(fid)) {
      return _notSent<ForumFavoriteReceipt>('favorite_forum_fid_invalid');
    }
    if (request.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent<ForumFavoriteReceipt>();
    }

    String? remoteFavoriteId;
    if (request.targetState == FavoriteTargetState.unfavorited) {
      final before = await _directory.load(
        FavoriteForumDirectoryQuery(cancellation: request.cancellation),
        cachePolicy: CacheLoadPolicy.networkFirst,
      );
      if (before
          case DataReadFailure<
                FavoriteForumDirectoryData,
                FavoriteForumDirectoryReadCapabilities
              >()) {
        return DataCommandNotSent<ForumFavoriteReceipt>(
          _failureFromRead(before, postSent: false),
        );
      }
      final success =
          before
              as DataReadSuccess<
                FavoriteForumDirectoryData,
                FavoriteForumDirectoryReadCapabilities
              >;
      if (!_supportsForumConfirmation(success.capabilities)) {
        return _notSent<ForumFavoriteReceipt>(
          'favorite_forum_directory_capability_missing',
          kind: DataCommandFailureKind.unsupported,
          retryPolicy: DataCommandRetryPolicy.never,
        );
      }
      FavoriteForumEntry? entry;
      for (final candidate in success.data.items) {
        if (candidate.fid.trim() == fid) {
          entry = candidate;
          break;
        }
      }
      if (entry == null) {
        return DataCommandApplied<ForumFavoriteReceipt>(
          ForumFavoriteReceipt(
            fid: fid,
            targetState: request.targetState,
            disposition: FavoriteMutationDisposition.alreadyApplied,
          ),
        );
      }
      remoteFavoriteId = entry.remoteFavoriteId?.trim();
      if (!_isPositiveIdentity(remoteFavoriteId ?? '')) {
        return _notSent<ForumFavoriteReceipt>(
          'favorite_forum_remote_identity_missing',
          kind: DataCommandFailureKind.parse,
        );
      }
      final known = request.knownRemoteFavoriteId?.trim();
      if (known != null && known.isNotEmpty && known != remoteFavoriteId) {
        return _notSent<ForumFavoriteReceipt>(
          'favorite_forum_remote_identity_mismatch',
        );
      }
    }

    final formhashResult = await _formhash.loadFormhash(
      preferProfile: true,
      cancellation: request.cancellation,
    );
    if (formhashResult case ForumFormhashError(:final failure)) {
      return DataCommandNotSent<ForumFavoriteReceipt>(
        _failureFromTransport(
          failure,
          retryPolicy: DataCommandRetryPolicy.afterSessionRefresh,
        ),
      );
    }
    final formhash = (formhashResult as ForumFormhashSuccess).value.trim();
    if (formhash.isEmpty) {
      return _notSent<ForumFavoriteReceipt>(
        'formhash_unavailable',
        kind: DataCommandFailureKind.staleFormhash,
        retryPolicy: DataCommandRetryPolicy.afterSessionRefresh,
      );
    }
    if (request.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent<ForumFavoriteReceipt>();
    }

    final response = request.targetState == FavoriteTargetState.favorited
        ? await _api.postForm(
            module: 'favforum',
            queryParameters: const <String, Object?>{'version': '4'},
            form: <String, String>{
              'formhash': formhash,
              'id': fid,
              'favoritesubmit': '1',
            },
            treatMessageAsBusinessError: false,
            cancellation: request.cancellation,
          )
        : await _api.postForm(
            module: 'favthread',
            queryParameters: <String, Object?>{
              'version': '4',
              'op': 'delete',
              'favid': remoteFavoriteId!,
            },
            form: <String, String>{
              'formhash': formhash,
              'deletesubmit': 'true',
            },
            treatMessageAsBusinessError: false,
            cancellation: request.cancellation,
          );
    final submission = _interpretSubmission(
      response,
      targetState: request.targetState,
    );
    if (submission case _SubmissionRejected(:final failure)) {
      return DataCommandRejected<ForumFavoriteReceipt>(failure);
    }
    if (submission case _SubmissionUnknown(:final failure)) {
      return DataCommandOutcomeUnknown<ForumFavoriteReceipt>(failure);
    }
    if (request.cancellation?.isCancelled ?? false) {
      return _cancelledUnknown<ForumFavoriteReceipt>();
    }

    final confirmation = await _directory.load(
      FavoriteForumDirectoryQuery(cancellation: request.cancellation),
      cachePolicy: CacheLoadPolicy.networkFirst,
    );
    if (confirmation
        case DataReadFailure<
              FavoriteForumDirectoryData,
              FavoriteForumDirectoryReadCapabilities
            >()) {
      return DataCommandOutcomeUnknown<ForumFavoriteReceipt>(
        _failureFromRead(confirmation, postSent: true),
      );
    }
    final confirmed =
        confirmation
            as DataReadSuccess<
              FavoriteForumDirectoryData,
              FavoriteForumDirectoryReadCapabilities
            >;
    if (!_supportsForumConfirmation(confirmed.capabilities)) {
      return _unconfirmed<ForumFavoriteReceipt>(
        'favorite_forum_directory_capability_missing',
      );
    }
    FavoriteForumEntry? confirmedEntry;
    for (final candidate in confirmed.data.items) {
      if (candidate.fid.trim() == fid) {
        confirmedEntry = candidate;
        break;
      }
    }
    final isFavorited = confirmedEntry != null;
    if (isFavorited != (request.targetState == FavoriteTargetState.favorited)) {
      return _unconfirmed<ForumFavoriteReceipt>(
        'favorite_forum_state_unconfirmed',
      );
    }
    return DataCommandApplied<ForumFavoriteReceipt>(
      ForumFavoriteReceipt(
        fid: fid,
        targetState: request.targetState,
        disposition: (submission as _SubmissionAccepted).disposition,
        remoteFavoriteId: confirmedEntry?.remoteFavoriteId?.trim(),
      ),
    );
  }
}

/// Experimental Discuz v4 command for thread favorite target states.
final class DiscuzFavoriteThreadCommandAdapter
    implements FavoriteThreadCommand {
  /// Creates the command around the shared API, formhash, and directory ports.
  const DiscuzFavoriteThreadCommandAdapter(
    this._api,
    this._formhash,
    this._directory,
  );

  final DiscuzApiClient _api;
  final ForumFormhashProvider _formhash;
  final FavoriteThreadDirectoryRepository _directory;

  @override
  FavoriteMutationCapabilities get capabilities =>
      _favoriteMutationCapabilities;

  @override
  Future<DataCommandResult<ThreadFavoriteReceipt>> execute(
    SetThreadFavoriteRequest request,
  ) async {
    final tid = request.tid.trim();
    if (!_isPositiveIdentity(tid)) {
      return _notSent<ThreadFavoriteReceipt>('favorite_thread_tid_invalid');
    }
    if (request.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent<ThreadFavoriteReceipt>();
    }
    final formhashResult = await _formhash.loadFormhash(
      preferProfile: true,
      cancellation: request.cancellation,
    );
    if (formhashResult case ForumFormhashError(:final failure)) {
      return DataCommandNotSent<ThreadFavoriteReceipt>(
        _failureFromTransport(
          failure,
          retryPolicy: DataCommandRetryPolicy.afterSessionRefresh,
        ),
      );
    }
    final formhash = (formhashResult as ForumFormhashSuccess).value.trim();
    if (formhash.isEmpty) {
      return _notSent<ThreadFavoriteReceipt>(
        'formhash_unavailable',
        kind: DataCommandFailureKind.staleFormhash,
        retryPolicy: DataCommandRetryPolicy.afterSessionRefresh,
      );
    }
    if (request.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent<ThreadFavoriteReceipt>();
    }

    final response = request.targetState == FavoriteTargetState.favorited
        ? await _api.postForm(
            module: 'favthread',
            queryParameters: const <String, Object?>{'version': '4'},
            form: <String, String>{
              'formhash': formhash,
              'id': tid,
              'favoritesubmit': '1',
            },
            referer: _api.config.siteOrigin
                .resolve('/forum.php')
                .replace(
                  queryParameters: <String, String>{
                    'mod': 'viewthread',
                    'tid': tid,
                    'mobile': '2',
                  },
                ),
            treatMessageAsBusinessError: false,
            cancellation: request.cancellation,
          )
        : await _api.postForm(
            module: 'favthread',
            queryParameters: <String, Object?>{
              'version': '4',
              'op': 'delete',
              'type': 'thread',
              'id': tid,
            },
            form: <String, String>{
              'formhash': formhash,
              'deletesubmit': 'true',
            },
            referer: _api.config.siteOrigin
                .resolve('/home.php')
                .replace(
                  queryParameters: const <String, String>{
                    'mod': 'spacecp',
                    'ac': 'favorite',
                    'mobile': '2',
                  },
                ),
            treatMessageAsBusinessError: false,
            cancellation: request.cancellation,
          );
    final submission = _interpretSubmission(
      response,
      targetState: request.targetState,
    );
    if (submission case _SubmissionRejected(:final failure)) {
      return DataCommandRejected<ThreadFavoriteReceipt>(failure);
    }
    if (submission case _SubmissionUnknown(:final failure)) {
      return DataCommandOutcomeUnknown<ThreadFavoriteReceipt>(failure);
    }
    if (request.cancellation?.isCancelled ?? false) {
      return _cancelledUnknown<ThreadFavoriteReceipt>();
    }

    final confirmation = await _confirmThreadState(
      directory: _directory,
      tid: tid,
      targetState: request.targetState,
      cancellation: request.cancellation,
    );
    if (confirmation case _ThreadConfirmationFailure(:final failure)) {
      return DataCommandOutcomeUnknown<ThreadFavoriteReceipt>(failure);
    }
    final confirmed = confirmation as _ThreadConfirmationSuccess;
    return DataCommandApplied<ThreadFavoriteReceipt>(
      ThreadFavoriteReceipt(
        tid: tid,
        targetState: request.targetState,
        disposition: (submission as _SubmissionAccepted).disposition,
        remoteFavoriteId: confirmed.remoteFavoriteId,
      ),
    );
  }
}

sealed class _SubmissionResult {
  const _SubmissionResult();
}

final class _SubmissionAccepted extends _SubmissionResult {
  const _SubmissionAccepted(this.disposition);
  final FavoriteMutationDisposition disposition;
}

final class _SubmissionRejected extends _SubmissionResult {
  const _SubmissionRejected(this.failure);
  final DataCommandFailure failure;
}

final class _SubmissionUnknown extends _SubmissionResult {
  const _SubmissionUnknown(this.failure);
  final DataCommandFailure failure;
}

_SubmissionResult _interpretSubmission(
  ForumTransportResult<ForumResponse<DiscuzApiEnvelope>> result, {
  required FavoriteTargetState targetState,
}) {
  if (result case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
    :final failure,
  )) {
    return _SubmissionUnknown(
      _failureFromTransport(
        failure,
        retryPolicy: DataCommandRetryPolicy.explicitOnly,
        cancellationWasAfterSend: true,
      ),
    );
  }
  final envelope =
      (result as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
          .response
          .body;
  final message = envelope.message;
  if (message == null || message.isEmpty) {
    return const _SubmissionUnknown(
      DataCommandFailure(
        kind: DataCommandFailureKind.parse,
        retryPolicy: DataCommandRetryPolicy.explicitOnly,
        code: 'favorite_mutation_response_unproved',
        diagnosticMessage: 'favorite_mutation_response_unproved',
      ),
    );
  }
  final code = message['messageval']?.toString().trim() ?? '';
  final text = message['messagestr']?.toString().trim() ?? '';
  final loweredCode = code.toLowerCase();
  final loweredText = text.toLowerCase();
  final alreadyApplied = targetState == FavoriteTargetState.favorited
      ? _isAlreadyFavorited(loweredCode, loweredText)
      : _isAlreadyUnfavorited(loweredCode, loweredText);
  if (alreadyApplied) {
    return const _SubmissionAccepted(
      FavoriteMutationDisposition.alreadyApplied,
    );
  }
  if (_isSuccess(loweredCode, loweredText)) {
    return const _SubmissionAccepted(FavoriteMutationDisposition.changed);
  }
  final staleFormhash = loweredCode.contains('formhash');
  final unauthenticated =
      loweredCode.contains('login') || loweredCode.contains('not_logged');
  return _SubmissionRejected(
    DataCommandFailure(
      kind: staleFormhash
          ? DataCommandFailureKind.staleFormhash
          : unauthenticated
          ? DataCommandFailureKind.unauthenticated
          : DataCommandFailureKind.permissionDenied,
      retryPolicy: staleFormhash
          ? DataCommandRetryPolicy.afterSessionRefresh
          : DataCommandRetryPolicy.explicitOnly,
      code: code.isEmpty ? 'favorite_mutation_rejected' : code,
      diagnosticMessage: code.isEmpty ? 'favorite_mutation_rejected' : code,
    ),
  );
}

bool _isSuccess(String code, String text) =>
    code.contains('success') ||
    code.contains('succeed') ||
    code == 'favorite_do_success' ||
    code == 'do_success' ||
    text.contains('成功');

bool _isAlreadyFavorited(String code, String text) =>
    code.contains('favorite_repeat') ||
    code.contains('favorite_already') ||
    code.contains('favorite_exists') ||
    code.contains('already') ||
    code.contains('exist') ||
    text.contains('已收藏') ||
    text.contains('已经收藏') ||
    text.contains('收藏过');

bool _isAlreadyUnfavorited(String code, String text) =>
    code.contains('favorite_does_not_exist') ||
    code.contains('not_exist') ||
    code.contains('noexist') ||
    code.contains('notfound') ||
    text.contains('未收藏') ||
    text.contains('不存在') ||
    text.contains('没有收藏');

bool _supportsForumConfirmation(
  FavoriteForumDirectoryReadCapabilities capabilities,
) =>
    capabilities.supports(
      FavoriteForumDirectoryCapability.stableForumIdentity,
    ) &&
    capabilities.supports(
      FavoriteForumDirectoryCapability.stableRemoteFavoriteIdentity,
    );

sealed class _ThreadConfirmation {
  const _ThreadConfirmation();
}

final class _ThreadConfirmationSuccess extends _ThreadConfirmation {
  const _ThreadConfirmationSuccess(this.remoteFavoriteId);
  final String? remoteFavoriteId;
}

final class _ThreadConfirmationFailure extends _ThreadConfirmation {
  const _ThreadConfirmationFailure(this.failure);
  final DataCommandFailure failure;
}

Future<_ThreadConfirmation> _confirmThreadState({
  required FavoriteThreadDirectoryRepository directory,
  required String tid,
  required FavoriteTargetState targetState,
  required ForumRequestCancellation? cancellation,
}) async {
  final seenTids = <String>{};
  final seenRemoteIds = <String>{};
  int? expectedTotalPages;
  for (var page = 1; ; page += 1) {
    if (cancellation?.isCancelled ?? false) {
      return _ThreadConfirmationFailure(_cancelledFailure(postSent: true));
    }
    final result = await directory.load(
      FavoriteThreadDirectoryQuery(page: page, cancellation: cancellation),
      cachePolicy: CacheLoadPolicy.networkFirst,
    );
    if (result
        case DataReadFailure<
              FavoriteThreadDirectoryData,
              FavoriteThreadDirectoryReadCapabilities
            >()) {
      return _ThreadConfirmationFailure(
        _failureFromRead(result, postSent: true),
      );
    }
    final success =
        result
            as DataReadSuccess<
              FavoriteThreadDirectoryData,
              FavoriteThreadDirectoryReadCapabilities
            >;
    final capabilities = success.capabilities;
    if (!capabilities.supports(
          FavoriteThreadDirectoryCapability.stableThreadIdentity,
        ) ||
        !capabilities.supports(
          FavoriteThreadDirectoryCapability.totalPageCount,
        ) ||
        capabilities.paginationPrecision != PaginationPrecision.exact) {
      return const _ThreadConfirmationFailure(
        DataCommandFailure(
          kind: DataCommandFailureKind.unsupported,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'favorite_thread_directory_capability_missing',
          diagnosticMessage: 'favorite_thread_directory_capability_missing',
        ),
      );
    }
    final pagination = success.data.pagination;
    final totalPages = pagination.totalPages;
    if (pagination.currentPage != page ||
        totalPages == null ||
        totalPages < 1) {
      return const _ThreadConfirmationFailure(
        DataCommandFailure(
          kind: DataCommandFailureKind.parse,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'favorite_thread_pagination_invalid',
          diagnosticMessage: 'favorite_thread_pagination_invalid',
        ),
      );
    }
    expectedTotalPages ??= totalPages;
    if (expectedTotalPages != totalPages || page > totalPages) {
      return const _ThreadConfirmationFailure(
        DataCommandFailure(
          kind: DataCommandFailureKind.parse,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'favorite_thread_pagination_changed',
          diagnosticMessage: 'favorite_thread_pagination_changed',
        ),
      );
    }
    for (final item in success.data.items) {
      final itemTid = item.tid.trim();
      final remoteId = item.remoteFavoriteId?.trim();
      if (itemTid.isEmpty || !seenTids.add(itemTid)) {
        return const _ThreadConfirmationFailure(
          DataCommandFailure(
            kind: DataCommandFailureKind.parse,
            retryPolicy: DataCommandRetryPolicy.explicitOnly,
            code: 'favorite_thread_identity_duplicated',
            diagnosticMessage: 'favorite_thread_identity_duplicated',
          ),
        );
      }
      if (remoteId != null &&
          remoteId.isNotEmpty &&
          !seenRemoteIds.add(remoteId)) {
        return const _ThreadConfirmationFailure(
          DataCommandFailure(
            kind: DataCommandFailureKind.parse,
            retryPolicy: DataCommandRetryPolicy.explicitOnly,
            code: 'favorite_thread_remote_identity_duplicated',
            diagnosticMessage: 'favorite_thread_remote_identity_duplicated',
          ),
        );
      }
      if (itemTid == tid) {
        if (targetState == FavoriteTargetState.unfavorited) {
          return const _ThreadConfirmationFailure(
            DataCommandFailure(
              kind: DataCommandFailureKind.unknown,
              retryPolicy: DataCommandRetryPolicy.explicitOnly,
              code: 'favorite_thread_state_unconfirmed',
              diagnosticMessage: 'favorite_thread_state_unconfirmed',
            ),
          );
        }
        return _ThreadConfirmationSuccess(remoteId);
      }
    }
    if (page >= totalPages) {
      return targetState == FavoriteTargetState.unfavorited
          ? const _ThreadConfirmationSuccess(null)
          : const _ThreadConfirmationFailure(
              DataCommandFailure(
                kind: DataCommandFailureKind.unknown,
                retryPolicy: DataCommandRetryPolicy.explicitOnly,
                code: 'favorite_thread_state_unconfirmed',
                diagnosticMessage: 'favorite_thread_state_unconfirmed',
              ),
            );
    }
  }
}

bool _isPositiveIdentity(String value) => RegExp(r'^\d+$').hasMatch(value);

DataCommandNotSent<T> _notSent<T>(
  String code, {
  DataCommandFailureKind kind = DataCommandFailureKind.validation,
  DataCommandRetryPolicy retryPolicy = DataCommandRetryPolicy.afterInputChange,
}) => DataCommandNotSent<T>(
  DataCommandFailure(
    kind: kind,
    retryPolicy: retryPolicy,
    code: code,
    diagnosticMessage: code,
  ),
);

DataCommandNotSent<T> _cancelledNotSent<T>() =>
    DataCommandNotSent<T>(_cancelledFailure(postSent: false));

DataCommandOutcomeUnknown<T> _cancelledUnknown<T>() =>
    DataCommandOutcomeUnknown<T>(_cancelledFailure(postSent: true));

DataCommandOutcomeUnknown<T> _unconfirmed<T>(String code) =>
    DataCommandOutcomeUnknown<T>(
      DataCommandFailure(
        kind: DataCommandFailureKind.unknown,
        retryPolicy: DataCommandRetryPolicy.explicitOnly,
        code: code,
        diagnosticMessage: code,
      ),
    );

DataCommandFailure _cancelledFailure({required bool postSent}) =>
    DataCommandFailure(
      kind: DataCommandFailureKind.cancelled,
      retryPolicy: postSent
          ? DataCommandRetryPolicy.explicitOnly
          : DataCommandRetryPolicy.never,
      code: 'request_cancelled',
      diagnosticMessage: 'request_cancelled',
    );

DataCommandFailure _failureFromRead<T, C>(
  DataReadFailure<T, C> failure, {
  required bool postSent,
}) => DataCommandFailure(
  kind: switch (failure.kind) {
    DataReadFailureKind.network => DataCommandFailureKind.network,
    DataReadFailureKind.timeout => DataCommandFailureKind.timeout,
    DataReadFailureKind.unauthorized => DataCommandFailureKind.unauthenticated,
    DataReadFailureKind.server => DataCommandFailureKind.server,
    DataReadFailureKind.parse => DataCommandFailureKind.parse,
    DataReadFailureKind.business => DataCommandFailureKind.unknown,
    DataReadFailureKind.unsupported => DataCommandFailureKind.unsupported,
    DataReadFailureKind.cancelled => DataCommandFailureKind.cancelled,
    DataReadFailureKind.unknown => DataCommandFailureKind.unknown,
  },
  retryPolicy: postSent
      ? DataCommandRetryPolicy.explicitOnly
      : failure.kind == DataReadFailureKind.unauthorized
      ? DataCommandRetryPolicy.afterSessionRefresh
      : DataCommandRetryPolicy.explicitOnly,
  code: failure.code,
  statusCode: failure.statusCode,
  diagnosticMessage: failure.code ?? failure.diagnosticMessage,
);

DataCommandFailure _failureFromTransport(
  ForumTransportFailure failure, {
  DataCommandRetryPolicy retryPolicy = DataCommandRetryPolicy.explicitOnly,
  bool cancellationWasAfterSend = false,
}) => DataCommandFailure(
  kind: failure.statusCode == 405
      ? DataCommandFailureKind.securityChallenge
      : switch (failure.kind) {
          ForumTransportFailureKind.network => DataCommandFailureKind.network,
          ForumTransportFailureKind.timeout => DataCommandFailureKind.timeout,
          ForumTransportFailureKind.server => DataCommandFailureKind.server,
          ForumTransportFailureKind.unauthorized =>
            DataCommandFailureKind.unauthenticated,
          ForumTransportFailureKind.parse => DataCommandFailureKind.parse,
          ForumTransportFailureKind.business => DataCommandFailureKind.unknown,
          ForumTransportFailureKind.cancelled =>
            DataCommandFailureKind.cancelled,
          ForumTransportFailureKind.unknown => DataCommandFailureKind.unknown,
        },
  retryPolicy: failure.kind == ForumTransportFailureKind.cancelled
      ? cancellationWasAfterSend
            ? DataCommandRetryPolicy.explicitOnly
            : DataCommandRetryPolicy.never
      : retryPolicy,
  code: failure.code,
  statusCode: failure.statusCode,
  diagnosticMessage: failure.code,
);

final _favoriteMutationCapabilities = FavoriteMutationCapabilities(
  values: DataCapabilitySet.supported(FavoriteMutationCapability.values),
);
