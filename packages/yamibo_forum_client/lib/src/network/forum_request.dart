import 'dart:async';

enum ForumRequestMethod { get, post }

enum ForumResponseType { text, json, bytes }

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
