import 'forum_request.dart';
import 'forum_transport.dart';

/// A replay-safe file part used by a forum multipart request.
final class ForumMultipartFile {
  /// Creates a file part whose [openRead] returns a fresh stream every time.
  const ForumMultipartFile({
    required this.fieldName,
    required this.fileName,
    required this.contentType,
    required this.contentLength,
    required this.openRead,
  });

  /// Multipart form field name.
  final String fieldName;

  /// Safe file name sent to the server.
  final String fileName;

  /// Declared MIME type.
  final String contentType;

  /// Exact byte length of the stream.
  final int contentLength;

  /// Opens a new single-subscription stream for each transport attempt.
  final Stream<List<int>> Function() openRead;
}

/// One multipart request containing scalar fields and a single file.
final class ForumMultipartRequest {
  /// Creates a replay-safe multipart request.
  const ForumMultipartRequest({
    required this.uri,
    required this.context,
    required this.fields,
    required this.file,
    this.headers = const <String, String>{},
    this.followRedirects = true,
    this.cancellation,
    this.onSendProgress,
  });

  /// Destination URI.
  final Uri uri;

  /// Safe operation metadata.
  final ForumRequestContext context;

  /// Scalar multipart fields.
  final Map<String, String> fields;

  /// Single streamed file part.
  final ForumMultipartFile file;

  /// Additional non-sensitive headers.
  final Map<String, String> headers;

  /// Whether redirects may be followed by the Host transport.
  final bool followRedirects;

  /// Optional cooperative cancellation signal.
  final ForumRequestCancellation? cancellation;

  /// Optional upload progress callback in bytes.
  final void Function(int sent, int total)? onSendProgress;
}

/// Successful multipart response with a plain-text body.
final class ForumMultipartResponse {
  /// Creates a transport-safe multipart response.
  const ForumMultipartResponse({
    required this.uri,
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// Final response URI.
  final Uri uri;

  /// HTTP status code.
  final int? statusCode;

  /// Response headers.
  final Map<String, List<String>> headers;

  /// Plain response body used by the source adapter.
  final String body;
}

/// Host-overridable transport for streamed multipart commands.
abstract interface class ForumMultipartClient {
  /// Sends [request] without ordinary automatic retries.
  ///
  /// A Host may replay once only after a verified HTTP 405 WAF recovery. Each
  /// attempt must call [ForumMultipartFile.openRead] again.
  Future<ForumTransportResult<ForumMultipartResponse>> sendMultipart(
    ForumMultipartRequest request,
  );
}
