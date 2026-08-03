import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';

final class ComposerUnusedImageRemoteDocument {
  const ComposerUnusedImageRemoteDocument({
    required this.sourceUri,
    required this.body,
  });

  final Uri sourceUri;
  final String body;
}

abstract interface class ComposerUnusedImageRemoteDataSource {
  Future<ApiResult<ComposerUnusedImageRemoteDocument>> load(Uri uri);

  Future<ApiResult<ComposerUnusedImageRemoteDocument>> delete(Uri uri);
}

final class DiscuzComposerUnusedImageRemoteDataSource
    implements ComposerUnusedImageRemoteDataSource {
  const DiscuzComposerUnusedImageRemoteDataSource({
    required YamiboHttpGateway gateway,
  }) : _gateway = gateway;

  final YamiboHttpGateway _gateway;

  @override
  Future<ApiResult<ComposerUnusedImageRemoteDocument>> load(Uri uri) async {
    final result = await _gateway.getText(
      uri,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'composer.unused_images.list',
        pageKind: 'composer.unused_images',
      ),
    );
    return result.when(
      success: (response) => ApiSuccess(
        ComposerUnusedImageRemoteDocument(
          sourceUri: response.uri,
          body: response.body,
        ),
      ),
      failure: ApiFailure.new,
    );
  }

  @override
  Future<ApiResult<ComposerUnusedImageRemoteDocument>> delete(Uri uri) async {
    final result = await _gateway.getText(
      uri,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'composer.unused_images.delete',
        pageKind: 'composer.unused_images',
        silent: true,
      ),
    );
    return result.when(
      success: (response) => ApiSuccess(
        ComposerUnusedImageRemoteDocument(
          sourceUri: response.uri,
          body: response.body,
        ),
      ),
      failure: ApiFailure.new,
    );
  }
}
