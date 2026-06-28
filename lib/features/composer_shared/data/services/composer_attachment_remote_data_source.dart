import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_api_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

/// 抽象 Discuz `module=checkpost` 与 `module=forumupload` 两个端点。
/// 让仓储层只关心业务规则，不直接接触 dio / cookie。
abstract class ComposerAttachmentRemoteDataSource {
  Future<ComposerImageUploadPermission> checkUploadPermission({
    required String fid,
  });

  Future<ComposerImageUploadResponse> uploadImage({
    required String fid,
    required ComposerImageUploadPermission permission,
    required ComposerLocalImageFile file,
    void Function(int sent, int total)? onSendProgress,
  });
}

class DiscuzComposerAttachmentDioDataSource
    implements ComposerAttachmentRemoteDataSource {
  DiscuzComposerAttachmentDioDataSource({
    required CookieStore cookieStore,
    required YamiboApiClient apiClient,
    required YamiboHttpGateway gateway,
    Dio? dio,
  }) : _apiClient = apiClient,
       _gateway = gateway;

  static const Set<String> _imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
  };

  final YamiboApiClient _apiClient;
  final YamiboHttpGateway _gateway;

  @override
  Future<ComposerImageUploadPermission> checkUploadPermission({
    required String fid,
  }) async {
    final response = await _apiClient.getDiscuz(
      module: 'checkpost',
      queryParameters: <String, String>{'version': '1', 'fid': fid},
      treatMessageAsBusinessError: false,
    );
    if (response case ApiFailure(:final error)) {
      throw DioException(
        requestOptions: RequestOptions(path: AppConfig.apiBaseUrl),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: AppConfig.apiBaseUrl),
          statusCode: error.statusCode,
          data: error.raw,
        ),
        message: error.message,
      );
    }
    return _parsePermission(
      response.dataOrNull?.variables ?? const <String, dynamic>{},
    );
  }

  @override
  Future<ComposerImageUploadResponse> uploadImage({
    required String fid,
    required ComposerImageUploadPermission permission,
    required ComposerLocalImageFile file,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final multipartFile = await MultipartFile.fromFile(
      file.path,
      filename: file.fileName,
    );
    final endpoint = Uri.parse(AppConfig.apiBaseUrl).replace(
      queryParameters: <String, String>{
        'module': 'forumupload',
        'version': '4',
        'fid': fid,
        'type': 'image',
        'filetype': file.mimeType,
      },
    );
    final response = await _gateway.postMultipart(
      endpoint,
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.resource,
        operation: 'composer.attachment.upload',
        module: 'forumupload',
      ),
      data: FormData.fromMap(<String, dynamic>{
        'uid': permission.uid,
        'hash': permission.uploadHash,
        'Filedata': multipartFile,
      }),
      options: Options(
        responseType: ResponseType.plain,
        headers: const <String, String>{'accept': 'text/plain, */*'},
      ),
      onSendProgress: onSendProgress,
    );
    if (response case ApiFailure(:final error)) {
      throw DioException(
        requestOptions: RequestOptions(path: endpoint.toString()),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: endpoint.toString()),
          statusCode: error.statusCode,
          data: error.raw,
        ),
        message: error.message,
      );
    }
    final data = response.dataOrNull;
    final rawBody = data?.body;
    return ComposerImageUploadResponse(
      aid: rawBody?.toString().trim() ?? '',
      rawBody: rawBody,
      statusCode: data?.statusCode,
    );
  }

  ComposerImageUploadPermission _parsePermission(dynamic data) {
    final variables = _asJsonMap(data);
    final allowPerm = ParseUtils.asMap(variables['allowperm']);
    final allowUpload = ParseUtils.asMap(allowPerm['allowupload']);
    final attachRemain = ParseUtils.asMap(allowPerm['attachremain']);

    final allowedExtensions = <String>{};
    for (final entry in allowUpload.entries) {
      final extension = entry.key.trim().toLowerCase();
      if (!_imageExtensions.contains(extension)) {
        continue;
      }
      final value = ParseUtils.asInt(entry.value, fallback: 0);
      if (value == -1 || value > 0) {
        allowedExtensions.add(extension);
      }
    }

    return ComposerImageUploadPermission(
      uid: ParseUtils.asString(variables['member_uid']),
      username: ParseUtils.asString(variables['member_username']),
      formHash: ParseUtils.asString(variables['formhash']),
      uploadHash: ParseUtils.asString(allowPerm['uploadhash']),
      allowedExtensions: allowedExtensions,
      attachRemain: ComposerAttachRemain(
        size: ParseUtils.asInt(attachRemain['size'], fallback: 0),
        count: ParseUtils.asInt(attachRemain['count'], fallback: 0),
      ),
    );
  }

  JsonMap _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String) {
      final decoded = jsonDecode(data);
      return ParseUtils.asMap(decoded);
    }
    return <String, dynamic>{};
  }
}
