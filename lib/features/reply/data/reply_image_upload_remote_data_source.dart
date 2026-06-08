import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

abstract class ReplyImageUploadRemoteDataSource {
  Future<ReplyImageUploadPermission> checkUploadPermission({
    required String fid,
  });

  Future<ReplyImageUploadResponse> uploadImage({
    required String fid,
    required ReplyImageUploadPermission permission,
    required ReplyLocalImageFile file,
    void Function(int sent, int total)? onSendProgress,
  });
}

class DiscuzReplyImageUploadDioDataSource
    implements ReplyImageUploadRemoteDataSource {
  DiscuzReplyImageUploadDioDataSource({
    required CookieStore cookieStore,
    Dio? dio,
  })  : _cookieStore = cookieStore,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: AppConfig.connectTimeout,
                receiveTimeout: AppConfig.receiveTimeout,
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final cookieHeader = await _cookieStore.readCookieHeader(options.uri);
          if (cookieHeader != null && cookieHeader.isNotEmpty) {
            options.headers['cookie'] = cookieHeader;
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          final setCookie = response.headers.map['set-cookie'] ?? <String>[];
          await _cookieStore.saveFromSetCookie(
            response.requestOptions.uri,
            setCookie,
          );
          handler.next(response);
        },
      ),
    );
  }

  static const Set<String> _imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
  };

  final CookieStore _cookieStore;
  final Dio _dio;

  @override
  Future<ReplyImageUploadPermission> checkUploadPermission({
    required String fid,
  }) async {
    final response = await _dio.get<dynamic>(
      AppConfig.apiBaseUrl,
      queryParameters: <String, String>{
        'module': 'checkpost',
        'version': '1',
        'fid': fid,
      },
      options: Options(
        headers: const <String, String>{
          'accept': 'application/json, text/plain, */*',
        },
      ),
    );
    return _parsePermission(response.data);
  }

  @override
  Future<ReplyImageUploadResponse> uploadImage({
    required String fid,
    required ReplyImageUploadPermission permission,
    required ReplyLocalImageFile file,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final multipartFile = await MultipartFile.fromFile(
      file.path,
      filename: file.fileName,
    );
    final response = await _dio.post<dynamic>(
      AppConfig.apiBaseUrl,
      queryParameters: <String, String>{
        'module': 'forumupload',
        'version': '4',
        'fid': fid,
        'type': 'image',
        'filetype': file.mimeType,
      },
      data: FormData.fromMap(
        <String, dynamic>{
          'uid': permission.uid,
          'hash': permission.uploadHash,
          'Filedata': multipartFile,
        },
      ),
      options: Options(
        responseType: ResponseType.plain,
        headers: const <String, String>{
          'accept': 'text/plain, */*',
        },
      ),
      onSendProgress: onSendProgress,
    );
    final rawBody = response.data;
    return ReplyImageUploadResponse(
      aid: rawBody?.toString().trim() ?? '',
      rawBody: rawBody,
      statusCode: response.statusCode,
    );
  }

  ReplyImageUploadPermission _parsePermission(dynamic data) {
    final root = _asJsonMap(data);
    final variables = ParseUtils.asMap(root['Variables']);
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

    return ReplyImageUploadPermission(
      uid: ParseUtils.asString(variables['member_uid']),
      username: ParseUtils.asString(variables['member_username']),
      formHash: ParseUtils.asString(variables['formhash']),
      uploadHash: ParseUtils.asString(allowPerm['uploadhash']),
      allowedExtensions: allowedExtensions,
      attachRemain: ReplyAttachRemain(
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
