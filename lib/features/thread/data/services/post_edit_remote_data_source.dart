import 'package:dio/dio.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';

final class PostEditRemoteDocument {
  const PostEditRemoteDocument({required this.sourceUri, required this.html});

  final Uri sourceUri;
  final String html;
}

final class PostEditRemoteDeleteDocument {
  const PostEditRemoteDeleteDocument({
    required this.sourceUri,
    required this.body,
  });

  final Uri sourceUri;
  final String body;
}

final class PostEditRemoteSubmitDocument {
  const PostEditRemoteSubmitDocument({
    required this.sourceUri,
    required this.statusCode,
    required this.body,
  });

  final Uri sourceUri;
  final int? statusCode;
  final String body;
}

abstract interface class PostEditRemoteDataSource {
  Future<ApiResult<PostEditRemoteDocument>> get(Uri editUri);

  Future<ApiResult<PostEditRemoteDeleteDocument>> deleteImage(Uri deleteUri);

  Future<ApiResult<PostEditRemoteSubmitDocument>> submit({
    required Uri submitUri,
    required List<MapEntry<String, String>> fields,
  });
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

  @override
  Future<ApiResult<PostEditRemoteDeleteDocument>> deleteImage(
    Uri deleteUri,
  ) async {
    final result = await _gateway.getText(
      deleteUri,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post_edit.delete_attachment',
        pageKind: 'thread.post_edit',
        silent: true,
      ),
    );
    return result.when(
      success: (response) => ApiSuccess(
        PostEditRemoteDeleteDocument(
          sourceUri: response.uri,
          body: response.body,
        ),
      ),
      failure: ApiFailure.new,
    );
  }

  @override
  Future<ApiResult<PostEditRemoteSubmitDocument>> submit({
    required Uri submitUri,
    required List<MapEntry<String, String>> fields,
  }) async {
    final formData = FormData();
    formData.fields.addAll(fields);
    final result = await _gateway.postMultipart(
      submitUri,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'thread.post_edit.submit',
        pageKind: 'thread.post_edit',
        silent: true,
      ),
      data: formData,
      options: Options(
        responseType: ResponseType.plain,
        headers: const <String, String>{'accept': 'text/xml, text/plain, */*'},
      ),
    );
    return result.when(
      success: (response) => ApiSuccess(
        PostEditRemoteSubmitDocument(
          sourceUri: response.uri,
          statusCode: response.statusCode,
          body: response.body?.toString() ?? '',
        ),
      ),
      failure: ApiFailure.new,
    );
  }
}
