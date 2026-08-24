import '../network/forum_request.dart';

enum ForumResourceKind { image }

enum ForumResourceOrigin { sameSite, thirdParty }

final class ForumResourceReference {
  const ForumResourceReference({
    required this.uri,
    required this.referer,
    required this.kind,
    required this.origin,
  });

  final Uri uri;
  final Uri referer;
  final ForumResourceKind kind;
  final ForumResourceOrigin origin;
}

final class ForumResourceRequest {
  const ForumResourceRequest({
    required this.reference,
    this.ifNoneMatch,
    this.cancellation,
  });

  final ForumResourceReference reference;
  final String? ifNoneMatch;
  final ForumRequestCancellation? cancellation;
}

enum ForumResourceFailureKind {
  invalidReference,
  unsupported,
  network,
  timeout,
  unauthorized,
  notFound,
  server,
  securityChallenge,
  invalidContent,
  redirectRejected,
  cancelled,
  unknown,
}

final class ForumResourceFailure {
  const ForumResourceFailure({
    required this.kind,
    required this.code,
    this.statusCode,
  });

  final ForumResourceFailureKind kind;
  final String code;
  final int? statusCode;
}

sealed class ForumResourceResult {
  const ForumResourceResult();
}

final class ForumResourceSuccess extends ForumResourceResult {
  const ForumResourceSuccess({
    required this.uri,
    required this.statusCode,
    required this.content,
    required this.validUntil,
    this.contentLength,
    this.contentType,
    this.eTag,
    this.fileExtension = '',
  });

  final Uri uri;
  final int statusCode;
  final Stream<List<int>> content;
  final int? contentLength;
  final String? contentType;
  final String? eTag;
  final DateTime validUntil;

  /// Includes the leading dot when known, matching common cache-manager APIs.
  final String fileExtension;
}

final class ForumResourceError extends ForumResourceResult {
  const ForumResourceError(this.failure);

  final ForumResourceFailure failure;
}

final class ForumResourceStreamException implements Exception {
  const ForumResourceStreamException({
    required this.failure,
    required this.bytesReceived,
  });

  final ForumResourceFailure failure;
  final int bytesReceived;

  @override
  String toString() =>
      'ForumResourceStreamException(${failure.code}, bytes=$bytesReceived)';
}

abstract interface class ForumResourceClient {
  Future<ForumResourceResult> open(ForumResourceRequest request);
}

final class UnsupportedForumResourceClient implements ForumResourceClient {
  const UnsupportedForumResourceClient();

  @override
  Future<ForumResourceResult> open(ForumResourceRequest request) async =>
      const ForumResourceError(
        ForumResourceFailure(
          kind: ForumResourceFailureKind.unsupported,
          code: 'resource_client_not_installed',
        ),
      );
}

final class ForumResourceReferenceResolver {
  const ForumResourceReferenceResolver({required this.siteOrigin});

  final Uri siteOrigin;

  ForumResourceReference? resolve(
    String value, {
    Uri? referer,
    ForumResourceKind kind = ForumResourceKind.image,
  }) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    final uri = parsed.isAbsolute ? parsed : siteOrigin.resolveUri(parsed);
    if (!_isHttp(uri) || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return null;
    }
    final sameSite = _isSameSite(uri);
    return ForumResourceReference(
      uri: uri.removeFragment(),
      referer: _sanitizeReferer(referer, forThirdParty: !sameSite),
      kind: kind,
      origin: sameSite
          ? ForumResourceOrigin.sameSite
          : ForumResourceOrigin.thirdParty,
    );
  }

  Uri _sanitizeReferer(Uri? candidate, {required bool forThirdParty}) {
    final value = candidate;
    if (value == null || !_isSameSite(value)) {
      return _withoutQuery(siteOrigin.replace(path: '/').removeFragment());
    }
    final withoutFragment = value.removeFragment();
    return forThirdParty ? _withoutQuery(withoutFragment) : withoutFragment;
  }

  Uri _withoutQuery(Uri uri) => Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  );

  bool _isSameSite(Uri uri) =>
      _isHttp(uri) &&
      uri.host.toLowerCase() == siteOrigin.host.toLowerCase() &&
      uri.port == siteOrigin.port;

  bool _isHttp(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';
}
