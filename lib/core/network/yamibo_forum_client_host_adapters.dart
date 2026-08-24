import 'dart:async';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart' as forum;
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo.dart';
import 'package:y300/features/auth/domain/services/formhash_provider.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

/// Routes package reads through Y300's single Cookie/session/WAF transport.
final class Y300ForumClientNetworkAdapter
    implements forum.ForumClientNetwork, forum.ForumResourceClient {
  const Y300ForumClientNetworkAdapter({
    required YamiboHttpGateway gateway,
    required Uri apiOrigin,
    required Uri siteOrigin,
    required String resourceUserAgent,
  }) : _gateway = gateway,
       _apiOrigin = apiOrigin,
       _siteOrigin = siteOrigin,
       _resourceUserAgent = resourceUserAgent;

  final YamiboHttpGateway _gateway;
  final Uri _apiOrigin;
  final Uri _siteOrigin;
  final String _resourceUserAgent;

  @override
  Future<forum.ForumResourceResult> open(
    forum.ForumResourceRequest request,
  ) async {
    final reference =
        forum.ForumResourceReferenceResolver(siteOrigin: _siteOrigin).resolve(
          request.reference.uri.toString(),
          referer: request.reference.referer,
          kind: request.reference.kind,
        );
    if (reference == null || reference.kind != forum.ForumResourceKind.image) {
      return const forum.ForumResourceError(
        forum.ForumResourceFailure(
          kind: forum.ForumResourceFailureKind.invalidReference,
          code: 'invalid_resource_reference',
        ),
      );
    }
    final cancelToken = CancelToken();
    final cancellation = request.cancellation;
    if (cancellation != null) {
      unawaited(
        cancellation.whenCancelled.then((_) {
          if (!cancelToken.isCancelled) cancelToken.cancel('request_cancelled');
        }),
      );
    }
    final result = await _gateway.openImageResource(
      reference.uri,
      referer: reference.referer,
      userAgent: _resourceUserAgent,
      ifNoneMatch: request.ifNoneMatch,
      cancelToken: cancelToken,
    );
    return switch (result) {
      ApiSuccess<YamiboResourceStreamResponse>(:final data) =>
        forum.ForumResourceSuccess(
          uri: data.uri,
          statusCode: data.statusCode,
          content: _mapResourceStream(data.content),
          contentLength: data.contentLength,
          contentType: data.contentType,
          eTag: data.eTag,
          validUntil: data.validUntil,
          fileExtension: data.fileExtension,
        ),
      ApiFailure<YamiboResourceStreamResponse>(:final error) =>
        forum.ForumResourceError(_mapResourceError(error)),
    };
  }

  Stream<List<int>> _mapResourceStream(Stream<List<int>> source) async* {
    try {
      yield* source;
    } on YamiboResourceStreamException catch (error) {
      throw forum.ForumResourceStreamException(
        failure: _mapResourceError(error.error),
        bytesReceived: error.bytesReceived,
      );
    }
  }

  forum.ForumResourceFailure _mapResourceError(ApiError error) {
    final code = error.code ?? error.type.name;
    final kind = switch (code) {
      'invalid_resource_reference' =>
        forum.ForumResourceFailureKind.invalidReference,
      'resource_redirect_rejected' =>
        forum.ForumResourceFailureKind.redirectRejected,
      'resource_not_found' => forum.ForumResourceFailureKind.notFound,
      'resource_is_not_image' => forum.ForumResourceFailureKind.invalidContent,
      'security_challenge_persisted' || 'security_verification_not_completed' =>
        forum.ForumResourceFailureKind.securityChallenge,
      'request_cancelled' => forum.ForumResourceFailureKind.cancelled,
      _ => switch (error.type) {
        ApiErrorType.network => forum.ForumResourceFailureKind.network,
        ApiErrorType.timeout => forum.ForumResourceFailureKind.timeout,
        ApiErrorType.unauthorized =>
          forum.ForumResourceFailureKind.unauthorized,
        ApiErrorType.server => forum.ForumResourceFailureKind.server,
        ApiErrorType.parse => forum.ForumResourceFailureKind.invalidContent,
        ApiErrorType.business => forum.ForumResourceFailureKind.server,
        ApiErrorType.unknown => forum.ForumResourceFailureKind.unknown,
      },
    };
    return forum.ForumResourceFailure(
      kind: kind,
      code: code,
      statusCode: error.statusCode,
    );
  }

  @override
  Future<forum.ForumTransportResult<forum.ForumResponse<Object?>>> send(
    forum.ForumRequest request,
  ) async {
    final cancelToken = CancelToken();
    final cancellation = request.cancellation;
    if (cancellation != null) {
      unawaited(
        cancellation.whenCancelled.then((_) {
          if (!cancelToken.isCancelled) {
            cancelToken.cancel('request_cancelled');
          }
        }),
      );
    }
    final context = YamiboRequestContext(
      kind: _requestKind(request),
      operation: request.context.operation,
      module: request.context.module,
      pageKind: request.context.pageKind,
      silent: request.context.silent,
    );

    if (request.method == forum.ForumRequestMethod.get) {
      return switch (request.responseType) {
        forum.ForumResponseType.text => _mapResult(
          await _gateway.getText(
            request.uri,
            context: context,
            headers: request.headers,
            cancelToken: cancelToken,
            followRedirects: request.followRedirects,
          ),
        ),
        forum.ForumResponseType.json => _mapResult(
          await _gateway.getJson(
            request.uri,
            context: context,
            headers: request.headers,
            cancelToken: cancelToken,
          ),
        ),
        forum.ForumResponseType.bytes => _mapResult(
          await _gateway.getBytes(
            request.uri,
            context: context,
            headers: request.headers,
            cancelToken: cancelToken,
          ),
        ),
      };
    }

    final body = request.body;
    if (body is! Map<String, String>) {
      return const forum.ForumTransportError(
        forum.ForumTransportFailure(
          kind: forum.ForumTransportFailureKind.business,
          code: 'unsupported_request_body',
        ),
      );
    }
    return switch (request.responseType) {
      forum.ForumResponseType.text => _mapResult(
        await _gateway.postForm(
          request.uri,
          context: context,
          data: body,
          headers: request.headers,
          cancelToken: cancelToken,
          followRedirects: request.followRedirects,
        ),
      ),
      forum.ForumResponseType.json => _mapResult(
        await _gateway.postFormJson(
          request.uri,
          context: context,
          data: body,
          headers: request.headers,
          cancelToken: cancelToken,
          followRedirects: request.followRedirects,
        ),
      ),
      forum.ForumResponseType.bytes => const forum.ForumTransportError(
        forum.ForumTransportFailure(
          kind: forum.ForumTransportFailureKind.business,
          code: 'unsupported_response_type',
        ),
      ),
    };
  }

  forum.ForumTransportResult<forum.ForumResponse<Object?>> _mapResult<T>(
    ApiResult<YamiboHttpResponse<T>> result,
  ) => switch (result) {
    ApiSuccess<YamiboHttpResponse<T>>(:final data) =>
      forum.ForumTransportSuccess(
        forum.ForumResponse<Object?>(
          uri: data.uri,
          statusCode: data.statusCode,
          headers: data.headers,
          body: data.body,
        ),
      ),
    ApiFailure<YamiboHttpResponse<T>>(:final error) =>
      forum.ForumTransportError(_mapError(error)),
  };

  YamiboRequestKind _requestKind(forum.ForumRequest request) {
    if (request.responseType == forum.ForumResponseType.bytes) {
      return YamiboRequestKind.resource;
    }
    if (request.uri.host.toLowerCase() == _apiOrigin.host.toLowerCase() &&
        request.uri.path == _apiOrigin.path) {
      return YamiboRequestKind.api;
    }
    return YamiboRequestKind.html;
  }

  forum.ForumTransportFailure _mapError(ApiError error) {
    final code = error.code?.trim();
    return forum.ForumTransportFailure(
      kind: code == 'request_cancelled'
          ? forum.ForumTransportFailureKind.cancelled
          : switch (error.type) {
              ApiErrorType.network => forum.ForumTransportFailureKind.network,
              ApiErrorType.timeout => forum.ForumTransportFailureKind.timeout,
              ApiErrorType.unauthorized =>
                forum.ForumTransportFailureKind.unauthorized,
              ApiErrorType.server => forum.ForumTransportFailureKind.server,
              ApiErrorType.parse => forum.ForumTransportFailureKind.parse,
              ApiErrorType.business => forum.ForumTransportFailureKind.business,
              ApiErrorType.unknown => forum.ForumTransportFailureKind.unknown,
            },
      code: code?.isNotEmpty == true ? code! : error.type.name,
      statusCode: error.statusCode,
    );
  }
}

final class Y300ForumFormhashAdapter implements forum.ForumFormhashProvider {
  const Y300ForumFormhashAdapter(this._delegate);
  final FormhashProvider _delegate;

  @override
  Future<forum.ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
  }) async {
    final result = await _delegate.loadFormhash(preferProfile: preferProfile);
    return switch (result) {
      ApiSuccess<String>(:final data) => forum.ForumFormhashSuccess(data),
      ApiFailure<String>(:final error) => forum.ForumFormhashError(
        _mapApiError(error),
      ),
    };
  }

  forum.ForumTransportFailure _mapApiError(ApiError error) =>
      forum.ForumTransportFailure(
        kind: switch (error.type) {
          ApiErrorType.network => forum.ForumTransportFailureKind.network,
          ApiErrorType.timeout => forum.ForumTransportFailureKind.timeout,
          ApiErrorType.unauthorized =>
            forum.ForumTransportFailureKind.unauthorized,
          ApiErrorType.server => forum.ForumTransportFailureKind.server,
          ApiErrorType.parse => forum.ForumTransportFailureKind.parse,
          ApiErrorType.business => forum.ForumTransportFailureKind.business,
          ApiErrorType.unknown =>
            error.code == 'request_cancelled'
                ? forum.ForumTransportFailureKind.cancelled
                : forum.ForumTransportFailureKind.unknown,
        },
        code: error.code ?? error.type.name,
        statusCode: error.statusCode,
      );
}

final class Y300ForumSessionAdapter implements forum.ForumSessionStore {
  const Y300ForumSessionAdapter(this._delegate);

  final YamiboSessionStore _delegate;

  @override
  forum.ForumSessionSnapshot? readCurrent() {
    final value = _delegate.readCurrent();
    return value == null ? null : _toPackageSession(value);
  }

  @override
  String? readFreshFormhash() => _delegate.readFreshFormhash();

  @override
  Future<void> merge(forum.ForumSessionSnapshot snapshot) async {
    _delegate.saveExtracted(
      YamiboSessionSnapshot(
        isLoggedIn: snapshot.isLoggedIn,
        uid: snapshot.userId,
        username: snapshot.username,
        formhash: snapshot.formhash,
        updatedAt: snapshot.updatedAt,
        source: snapshot.source,
      ),
    );
  }

  @override
  Future<void> clear() async => _delegate.clear();
}

forum.ForumSessionSnapshot _toPackageSession(YamiboSessionSnapshot value) =>
    forum.ForumSessionSnapshot(
      isLoggedIn: value.isLoggedIn,
      userId: value.uid,
      username: value.username,
      formhash: value.formhash,
      updatedAt: value.updatedAt,
      source: value.source,
    );

final class Y300ForumDocumentStoreAdapter implements forum.ForumDocumentStore {
  const Y300ForumDocumentStoreAdapter(this._delegate);
  final DocumentCacheService _delegate;

  @override
  Future<forum.ForumCachedDocument?> get(
    forum.ForumDocumentDescriptor descriptor,
  ) async {
    final value = await _delegate.getByKey(descriptor.cacheKey);
    return value == null ? null : _toPackageDocument(value);
  }

  @override
  Future<void> put(forum.ForumCachedDocument document) =>
      _delegate.put(_toAppDocument(document));

  @override
  Future<void> touch(
    forum.ForumDocumentDescriptor descriptor,
    DateTime accessedAt,
  ) => _delegate.touch(descriptor.cacheKey, accessedAt);
}

final class Y300ForumSnapshotStoreAdapter implements forum.ForumSnapshotStore {
  const Y300ForumSnapshotStoreAdapter(this._delegate);
  final ParsedSnapshotCacheService _delegate;

  @override
  Future<forum.ForumCachedSnapshot<T>?> get<T>(
    forum.ForumSnapshotDescriptor descriptor,
    forum.ForumSnapshotCodec<T> codec,
  ) async {
    final value = await _delegate.get<T>(
      _toAppSnapshotDescriptor(descriptor),
      _Y300SnapshotCodec<T>(codec),
    );
    if (value == null) return null;
    return forum.ForumCachedSnapshot<T>(
      descriptor: descriptor,
      codecVersion: value.codecVersion,
      parserVersion: value.parserVersion,
      value: value.value,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt,
      lastAccessedAt: value.lastAccessedAt,
      staleAt: value.staleAt,
      expiresAt: value.expiresAt,
    );
  }

  @override
  Future<void> put<T>(
    forum.ForumSnapshotDescriptor descriptor,
    T value,
    forum.ForumSnapshotCodec<T> codec, {
    required forum.ForumSnapshotPolicy policy,
  }) => _delegate.put<T>(
    _toAppSnapshotDescriptor(descriptor),
    value,
    _Y300SnapshotCodec<T>(codec),
    policy: SnapshotCachePolicy(
      freshFor: policy.freshFor,
      keepStaleFor: policy.keepStaleFor,
    ),
  );

  @override
  Future<void> touch(
    forum.ForumSnapshotDescriptor descriptor,
    DateTime accessedAt,
  ) => _delegate.touch(descriptor.cacheKey, accessedAt);
}

/// Persists the package-owned sticker catalog codec in Y300's existing path.
final class Y300ForumStickerCatalogStore
    implements forum.ForumStickerCatalogStore {
  const Y300ForumStickerCatalogStore({Future<String> Function()? cacheFilePath})
    : _cacheFilePath = cacheFilePath ?? _defaultCacheFilePath;

  final Future<String> Function() _cacheFilePath;

  @override
  Future<String?> read() async {
    final file = io.File(await _cacheFilePath());
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String encoded) async {
    final file = io.File(await _cacheFilePath());
    await file.parent.create(recursive: true);
    await file.writeAsString(encoded, flush: true);
  }

  @override
  Future<void> clear() async {
    final file = io.File(await _cacheFilePath());
    if (await file.exists()) await file.delete();
  }

  static Future<String> _defaultCacheFilePath() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'cache', 'catalog', 'yamibo_smiley_v4.json');
  }
}

final class _Y300SnapshotCodec<T>
    implements SnapshotCodec<T>, SnapshotCodecVersionCompatibility {
  const _Y300SnapshotCodec(this.delegate);
  final forum.ForumSnapshotCodec<T> delegate;

  @override
  int get codecVersion => delegate.codecVersion;
  @override
  int get parserVersion => delegate.parserVersion;
  @override
  String get snapshotType => delegate.snapshotType;
  @override
  T decode(Object? json) => delegate.decode(json);
  @override
  Object? encode(T value) => delegate.encode(value);
  @override
  bool canDecodeVersion({
    required int codecVersion,
    required int parserVersion,
  }) => delegate.canDecodeVersion(
    codecVersion: codecVersion,
    parserVersion: parserVersion,
  );
}

forum.ForumCachedDocument _toPackageDocument(CachedDocument value) =>
    forum.ForumCachedDocument(
      descriptor: forum.ForumDocumentDescriptor(
        cacheKey: value.cacheKey,
        ownerType: value.ownerType.id,
        ownerId: value.ownerId,
        sourceUri: Uri.parse(value.sourceUrl),
        requestProfile: _toPackageProfile(value.requestProfile),
      ),
      body: value.body,
      contentType: value.contentType,
      statusCode: value.statusCode,
      fetchedAt: value.fetchedAt,
      updatedAt: value.updatedAt,
      lastAccessedAt: value.lastAccessedAt,
    );

CachedDocument _toAppDocument(forum.ForumCachedDocument value) =>
    CachedDocument(
      cacheKey: value.descriptor.cacheKey,
      ownerType: _ownerType(value.descriptor.ownerType),
      ownerId: value.descriptor.ownerId,
      sourceUrl: value.descriptor.sourceUri.toString(),
      requestProfile: _toAppProfile(value.descriptor.requestProfile),
      body: value.body,
      contentType: value.contentType,
      statusCode: value.statusCode,
      fetchedAt: value.fetchedAt,
      updatedAt: value.updatedAt,
      lastAccessedAt: value.lastAccessedAt,
    );

SnapshotCacheDescriptor _toAppSnapshotDescriptor(
  forum.ForumSnapshotDescriptor value,
) => SnapshotCacheDescriptor(
  cacheKey: value.cacheKey,
  ownerType: _ownerType(value.ownerType),
  ownerId: value.ownerId,
  snapshotType: value.snapshotType,
  sourceDocumentKey: value.sourceDocumentKey,
);

CacheOwnerType _ownerType(String id) => CacheOwnerType.values.firstWhere(
  (value) => value.id == id,
  orElse: () => throw StateError('unsupported_cache_owner:$id'),
);

forum.ForumDocumentRequestProfile _toPackageProfile(
  DocumentRequestProfile value,
) => switch (value) {
  DocumentRequestProfile.anonymous =>
    forum.ForumDocumentRequestProfile.anonymous,
  DocumentRequestProfile.loggedIn => forum.ForumDocumentRequestProfile.loggedIn,
};

DocumentRequestProfile _toAppProfile(forum.ForumDocumentRequestProfile value) =>
    switch (value) {
      forum.ForumDocumentRequestProfile.anonymous =>
        DocumentRequestProfile.anonymous,
      forum.ForumDocumentRequestProfile.loggedIn =>
        DocumentRequestProfile.loggedIn,
    };
