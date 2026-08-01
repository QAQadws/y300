import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';

final class PostEditRemoteDocument {
  const PostEditRemoteDocument({required this.sourceUri, required this.html});

  final Uri sourceUri;
  final String html;
}

abstract interface class PostEditRemoteDataSource {
  Future<ApiResult<PostEditRemoteDocument>> get(Uri editUri);
}

class DiscuzPostEditRemoteDataSource implements PostEditRemoteDataSource {
  const DiscuzPostEditRemoteDataSource({required YamiboHttpGateway gateway})
    : _gateway = gateway;

  final YamiboHttpGateway _gateway;

  @override
  Future<ApiResult<PostEditRemoteDocument>> get(Uri editUri) async {
    final result = await _gateway.getText(
      editUri,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post_edit.form',
        pageKind: 'thread.post_edit',
      ),
    );
    return result.when(
      success: (response) => ApiSuccess(
        PostEditRemoteDocument(sourceUri: response.uri, html: response.body),
      ),
      failure: ApiFailure.new,
    );
  }
}
