import 'forum_request.dart';
import 'forum_response.dart';
import 'forum_transport.dart';

abstract interface class ForumClientNetwork {
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  );
}
