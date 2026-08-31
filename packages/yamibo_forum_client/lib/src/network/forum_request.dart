import 'dart:async';

/// Values describing forum request method.
enum ForumRequestMethod {
  /// Get.
  get,

  /// Post.
  post,
}

/// Values describing forum response type.
enum ForumResponseType {
  /// Text.
  text,

  /// Json.
  json,

  /// Bytes.
  bytes,
}

/// Ordered URL-encoded form fields that may contain duplicate names.
///
/// A map cannot represent protocols such as Discuz poll submission where one
/// `pollanswers[]` field is emitted for every selected option. Transports must
/// preserve [entries] in order and encode every entry exactly once.
final class ForumFormFields {
  /// Creates an immutable ordered form body.
  ForumFormFields(Iterable<MapEntry<String, String>> entries)
    : entries = List<MapEntry<String, String>>.unmodifiable(entries);

  /// Ordered form fields, including duplicate field names.
  final List<MapEntry<String, String>> entries;

  /// Encodes these fields as `application/x-www-form-urlencoded` data.
  String encode() => entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');
}

/// Ordered scalar multipart fields that may contain duplicate names.
///
/// Unlike [ForumFormFields], this body is encoded as `multipart/form-data`.
/// Transports must create a fresh multipart container for every attempt so a
/// verified WAF replay never reuses consumed request state.
final class ForumMultipartFields {
  /// Creates immutable replay-safe multipart fields.
  ForumMultipartFields(Iterable<MapEntry<String, String>> entries)
    : entries = List<MapEntry<String, String>>.unmodifiable(entries);

  /// Ordered scalar fields, including duplicate names.
  final List<MapEntry<String, String>> entries;
}

/// Source-neutral forum request context.
final class ForumRequestContext {
  /// Creates a [ForumRequestContext].
  const ForumRequestContext({
    required this.operation,
    this.module,
    this.pageKind,
    this.silent = false,
  });

  /// Safe operation name used for diagnostics.
  final String operation;

  /// Source module name when applicable.
  final String? module;

  /// Source page kind when applicable.
  final String? pageKind;

  /// Whether Host logging should remain silent.
  final bool silent;
}

/// Source-neutral forum request cancellation.
final class ForumRequestCancellation {
  /// Creates a [ForumRequestCancellation].
  ForumRequestCancellation();
  bool _cancelled = false;
  final Completer<void> _completer = Completer<void>();

  /// Whether cancellation has already been requested.
  bool get isCancelled => _cancelled;

  /// Completes when cancellation is requested.
  Future<void> get whenCancelled => _completer.future;

  /// Signals cooperative cancellation.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _completer.complete();
  }
}

/// Validated request for forum.
final class ForumRequest {
  /// Creates a [ForumRequest].
  const ForumRequest({
    required this.method,
    required this.uri,
    required this.context,
    this.headers = const <String, String>{},
    this.body,
    this.responseType = ForumResponseType.text,
    this.followRedirects = true,
    this.cancellation,
  });

  /// Method.
  final ForumRequestMethod method;

  /// Validated resolved URI.
  final Uri uri;

  /// Context.
  final ForumRequestContext context;

  /// Headers.
  final Map<String, String> headers;

  /// Response or request body in the declared representation.
  final Object? body;

  /// Response type.
  final ForumResponseType responseType;

  /// Follow redirects.
  final bool followRedirects;

  /// Cancellation.
  final ForumRequestCancellation? cancellation;
}
