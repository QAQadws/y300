import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/reply_form_parser.dart';

abstract class ReplyFormPreparationDataSource {
  Future<ReplyPreparation> fetchReplyPreparation(Uri replyFormUri);
}

class DiscuzReplyFormPreparationDataSource
    implements ReplyFormPreparationDataSource {
  DiscuzReplyFormPreparationDataSource({
    required CookieStore cookieStore,
    ReplyFormParser parser = const ReplyFormParser(),
    Dio? dio,
  })  : _cookieStore = cookieStore,
        _parser = parser,
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
  final ReplyFormParser _parser;
  final Dio _dio;

  @override
  Future<ReplyPreparation> fetchReplyPreparation(Uri replyFormUri) async {
    final response = await _dio.get<String>(
      replyFormUri.toString(),
      options: Options(
        responseType: ResponseType.plain,
        headers: const <String, String>{
          'accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ),
    );
    final parsed = _parser.parse(
      sourceUri: replyFormUri,
      html: response.data ?? '',
    );
    if (parsed case ApiSuccess<ReplyPreparation>(:final data)) {
      return data;
    }
    final error = (parsed as ApiFailure<ReplyPreparation>).error;
    throw ReplyFormParseException(error.message);
  }
}

class ReplyFormParseException implements Exception {
  const ReplyFormParseException(this.message);

  final String message;

  @override
  String toString() => message;
}
