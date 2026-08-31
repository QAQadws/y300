/// Streaming contracts for protected and third-party forum image resources.
library;

import '../network/forum_request.dart';

/// Resource kinds supported by the package streaming boundary.
/// Values describing forum resource kind.
enum ForumResourceKind {
  /// Image.
  image,
}

/// Whether a resource shares the managed forum's authority.
/// Values describing forum resource origin.
enum ForumResourceOrigin {
  /// Same site.
  sameSite,

  /// Third party.
  thirdParty,
}

/// Validated resource identity and privacy-safe referer.
final class ForumResourceReference {
  /// Creates an already validated resource reference.
  const ForumResourceReference({
    required this.uri,
    required this.referer,
    required this.kind,
    required this.origin,
  });

  /// Requested resource URI.
  final Uri uri;

  /// Sanitized same-site referer.
  final Uri referer;

  /// Requested resource kind.
  final ForumResourceKind kind;

  /// Same-site classification used for Cookie and WAF isolation.
  final ForumResourceOrigin origin;
}

/// Request for one resource stream.
final class ForumResourceRequest {
  /// Creates a resource request.
  const ForumResourceRequest({
    required this.reference,
    this.ifNoneMatch,
    this.cancellation,
  });

  /// Validated resource reference.
  final ForumResourceReference reference;

  /// Optional ETag used for a conditional GET.
  final String? ifNoneMatch;

  /// Optional cooperative cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Stable failure categories for protected resource reads.
enum ForumResourceFailureKind {
  /// Invalid reference.
  invalidReference,

  /// Unsupported.
  unsupported,

  /// Network.
  network,

  /// Timeout.
  timeout,

  /// Unauthorized.
  unauthorized,

  /// Not found.
  notFound,

  /// Server.
  server,

  /// Security challenge.
  securityChallenge,

  /// Invalid content.
  invalidContent,

  /// Redirect rejected.
  redirectRejected,

  /// Cancelled.
  cancelled,

  /// Unknown.
  unknown,
}

/// Safe resource failure without response bodies or authentication data.
final class ForumResourceFailure {
  /// Creates a resource failure.
  const ForumResourceFailure({
    required this.kind,
    required this.code,
    this.statusCode,
  });

  /// Stable failure category.
  final ForumResourceFailureKind kind;

  /// Protocol-safe diagnostic code.
  final String code;

  /// Optional HTTP status code.
  final int? statusCode;
}

/// Result of opening a resource stream.
sealed class ForumResourceResult {
  const ForumResourceResult();
}

/// Successfully opened single-subscription resource stream.
final class ForumResourceSuccess extends ForumResourceResult {
  /// Creates a successful resource response.
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

  /// Final URI after accepted redirects.
  final Uri uri;

  /// HTTP response status, including 304 when applicable.
  final int statusCode;

  /// Byte stream that must be consumed once or cancelled.
  final Stream<List<int>> content;

  /// Declared response length when known.
  final int? contentLength;

  /// Validated response media type when supplied.
  final String? contentType;

  /// Response ETag used by Host caches.
  final String? eTag;

  /// Cache validity computed from response headers or package defaults.
  final DateTime validUntil;

  /// Includes the leading dot when known, matching common cache-manager APIs.
  final String fileExtension;
}

/// Resource request that failed before exposing usable bytes.
final class ForumResourceError extends ForumResourceResult {
  /// Creates an error result.
  const ForumResourceError(this.failure);

  /// Stable failure description.
  final ForumResourceFailure failure;
}

/// Typed failure raised after a resource stream has begun.
final class ForumResourceStreamException implements Exception {
  /// Creates a partial-stream exception.
  const ForumResourceStreamException({
    required this.failure,
    required this.bytesReceived,
  });

  /// Stable failure that terminated the stream.
  final ForumResourceFailure failure;

  /// Number of bytes exposed before the failure.
  final int bytesReceived;

  @override
  String toString() =>
      'ForumResourceStreamException(${failure.code}, bytes=$bytesReceived)';
}

/// Opens validated forum image references as single-subscription streams.
abstract interface class ForumResourceClient {
  /// Opens [request] without buffering the full resource.
  Future<ForumResourceResult> open(ForumResourceRequest request);
}

/// Fail-closed resource client used when no transport is installed.
final class UnsupportedForumResourceClient implements ForumResourceClient {
  /// Creates an unsupported resource client.
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

/// Validates and classifies resource references for one forum origin.
final class ForumResourceReferenceResolver {
  /// Creates a resolver for [siteOrigin].
  const ForumResourceReferenceResolver({required this.siteOrigin});

  /// Canonical managed forum origin.
  final Uri siteOrigin;

  /// Resolves the reference using the configured forum boundary.
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
