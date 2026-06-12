import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';

/// 发帖提交的 form-urlencoded 载荷。
///
/// 把"业务字段 → form key/value"集中在这里，让上层的 Repository / 测试
/// 不关心 Discuz 字段拼写细节。
class NewThreadSubmitForm {
  const NewThreadSubmitForm({
    required this.payload,
  });

  final NewThreadDraftPayload payload;

  Map<String, String> toFormData() {
    final attachmentAids = _normalizeAttachmentAids(
      payload.uploadedAttachmentAids,
    );
    return <String, String>{
      'formhash': payload.formHash,
      'topicsubmit': 'yes',
      'subject': payload.subject,
      'message': payload.message,
      'typeid': payload.typeid,
      // 第一期不实装投票/悬赏/活动，always 0。
      'special': '0',
      'usesig': payload.useSignature ? '1' : '0',
      'allownoticeauthor': payload.allowNoticeAuthor ? '1' : '0',
      if (payload.bbCodeOff) 'bbcodeoff': '1',
      if (payload.smileyOff) 'smileyoff': '1',
      if (payload.parseUrlOff) 'parseurloff': '1',
      if (attachmentAids.isNotEmpty) 'allowphoto': '1',
      for (final aid in attachmentAids) 'attachnew[$aid][description]': '',
    };
  }

  static List<String> _normalizeAttachmentAids(Iterable<String> aids) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final aid in aids) {
      final trimmed = aid.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      normalized.add(trimmed);
    }
    return normalized;
  }
}

class NewThreadRemoteResponse {
  const NewThreadRemoteResponse({
    required this.data,
    required this.statusCode,
  });

  final dynamic data;
  final int? statusCode;
}

abstract class NewThreadRemoteDataSource {
  Future<NewThreadRemoteResponse> submit(NewThreadSubmitForm form);
}

class DiscuzNewThreadDioRemoteDataSource implements NewThreadRemoteDataSource {
  DiscuzNewThreadDioRemoteDataSource({
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

  final CookieStore _cookieStore;
  final Dio _dio;

  @override
  Future<NewThreadRemoteResponse> submit(NewThreadSubmitForm form) async {
    final endpoint = '${AppConfig.siteBaseUrl}/api/mobile/index.php';
    final response = await _dio.post<dynamic>(
      endpoint,
      queryParameters: <String, String>{
        'module': 'newthread',
        'version': '4',
        'fid': form.payload.fid,
      },
      data: form.toFormData(),
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: <String, String>{
          'referer':
              '${AppConfig.siteBaseUrl}/forum.php?mod=post&action=newthread&fid=${form.payload.fid}',
          'accept': 'application/json, text/plain, */*',
        },
      ),
    );
    return NewThreadRemoteResponse(
      data: response.data,
      statusCode: response.statusCode,
    );
  }
}
