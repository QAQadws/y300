import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../waf/forum_waf.dart';

/// Discards proven edge denials before Dio decodes or wraps their payloads.
/// Status, headers, and redirects remain available to the recovery policy.
final class ForumWafHttpClientAdapter implements HttpClientAdapter {
  /// Wraps an existing adapter without changing ordinary response processing.
  ForumWafHttpClientAdapter({
    required this.delegate,
    required this.isManagedUri,
  });

  /// The transport adapter, including any platform-specific configuration.
  final HttpClientAdapter delegate;

  /// Host-owned boundary for requests eligible for forum recovery.
  final bool Function(Uri) isManagedUri;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await delegate.fetch(options, requestStream, cancelFuture);
    final finalUri = response.redirects?.isNotEmpty == true
        ? response.redirects!.last.location
        : options.uri;
    if (isManagedUri(options.uri) &&
        isManagedUri(finalUri) &&
        ForumWafResponsePolicy.classify(
              statusCode: response.statusCode,
              headers: response.headers,
            ) !=
            ForumWafResponseDecision.none) {
      // Close the raw stream before Dio's stream wrapper or JSON decoding.
      // A denial may claim application/json or image/* while returning HTML.
      try {
        await response.stream.listen(null).cancel();
      } catch (_) {
        // Cleanup failure must not hide the already established denial.
      }
      response.stream = const Stream.empty();
    }
    return response;
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}
