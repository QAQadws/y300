import 'dart:async';

enum ForumRequestMethod { get, post }

enum ForumResponseType { text, json, bytes }

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

final class ForumRequestContext {
  const ForumRequestContext({
    required this.operation,
    this.module,
    this.pageKind,
    this.silent = false,
  });
  final String operation;
  final String? module;
  final String? pageKind;
  final bool silent;
}

final class ForumRequestCancellation {
  ForumRequestCancellation();
  bool _cancelled = false;
  final Completer<void> _completer = Completer<void>();
  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _completer.future;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _completer.complete();
  }
}

final class ForumRequest {
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

  final ForumRequestMethod method;
  final Uri uri;
  final ForumRequestContext context;
  final Map<String, String> headers;
  final Object? body;
  final ForumResponseType responseType;
  final bool followRedirects;
  final ForumRequestCancellation? cancellation;
}
