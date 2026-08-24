import 'forum_request.dart';
import 'forum_response.dart';
import 'forum_transport.dart';

/// Host-overridable transport used by all structured forum reads.
abstract interface class ForumClientNetwork {
  /// Sends a normalized request and returns a transport-safe response.
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  );
}
