import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/reply/data/discuz_reply_remote_data_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiscuzReplyDioRemoteDataSource', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('posts sendreply payload with expected query headers and body', () async {
      final adapter = _ReplyRemoteTestAdapter(
        responseJson: <String, dynamic>{
          'Message': <String, dynamic>{
            'messageval': 'post_reply_succeed',
            'messagestr': '回复发布成功',
          },
        },
      );
      final dataSource = _buildDataSource(adapter);

      final response = await dataSource.sendReply(
        const ReplySubmitPayload(
          formHash: 'fe182126',
          fid: '33',
          tid: '570617',
          message: '测试回复',
          useSignature: true,
        ),
      );

      expect(response.statusCode, 200);
      expect(response.data, contains('post_reply_succeed'));
      expect(adapter.lastUri.queryParameters['module'], 'sendreply');
      expect(adapter.lastUri.queryParameters['version'], '4');
      expect(adapter.lastBody, contains('formhash=fe182126'));
      expect(adapter.lastBody, contains('fid=33'));
      expect(adapter.lastBody, contains('tid=570617'));
      expect(
        adapter.lastBody,
        contains('message=%E6%B5%8B%E8%AF%95%E5%9B%9E%E5%A4%8D'),
      );
      expect(adapter.lastBody, contains('replysubmit=yes'));
      expect(adapter.lastBody, contains('usesig=1'));
      expect(adapter.lastHeaders['accept'], 'application/json, text/plain, */*');
      expect(
        adapter.lastHeaders['referer'],
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=570617&mobile=2',
      );
    });

    test('maps disabled signature to usesig zero', () async {
      final adapter = _ReplyRemoteTestAdapter(responseJson: <String, dynamic>{});
      final dataSource = _buildDataSource(adapter);

      await dataSource.sendReply(
        const ReplySubmitPayload(
          formHash: 'fe182126',
          fid: '33',
          tid: '570617',
          message: '测试回复',
          useSignature: false,
        ),
      );

      expect(adapter.lastBody, contains('usesig=0'));
    });

    test('passes optional post reply fields through form body', () async {
      final adapter = _ReplyRemoteTestAdapter(responseJson: <String, dynamic>{});
      final dataSource = _buildDataSource(adapter);

      await dataSource.sendReply(
        const ReplySubmitPayload(
          formHash: 'fe182126',
          fid: '33',
          tid: '570617',
          message: '测试回复',
          useSignature: true,
          repPid: '41554317',
          repPost: '41554317',
          noticeAuthor: 'notice-token',
          noticeTrimStr: '[quote]引用[/quote]',
          noticeAuthorMsg: '引用正文',
        ),
      );

      expect(adapter.lastBody, contains('reppid=41554317'));
      expect(adapter.lastBody, contains('reppost=41554317'));
      expect(adapter.lastBody, contains('noticeauthor=notice-token'));
      expect(adapter.lastBody, contains('noticetrimstr='));
      expect(adapter.lastBody, contains('noticeauthormsg='));
    });

    test('adds cookies from cookie store and saves response cookies', () async {
      final adapter = _ReplyRemoteTestAdapter(
        responseJson: <String, dynamic>{},
        responseHeaders: const <String, List<String>>{
          'set-cookie': <String>['next_cookie=456; Path=/'],
        },
      );
      final cookieStore = CookieStore();
      final uri = Uri.parse('https://bbs.yamibo.com/api/mobile/index.php');
      await cookieStore.saveFromSetCookie(
        uri,
        const <String>['reply_cookie=123; Path=/'],
      );
      final dataSource = _buildDataSource(adapter, cookieStore: cookieStore);

      await dataSource.sendReply(
        const ReplySubmitPayload(
          formHash: 'fe182126',
          fid: '33',
          tid: '570617',
          message: '测试回复',
          useSignature: true,
        ),
      );

      expect(adapter.lastHeaders['cookie'], contains('reply_cookie=123'));
      final cookieHeader = await cookieStore.readCookieHeader(uri);
      expect(cookieHeader, contains('next_cookie=456'));
    });
  });
}

DiscuzReplyDioRemoteDataSource _buildDataSource(
  _ReplyRemoteTestAdapter adapter, {
  CookieStore? cookieStore,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return DiscuzReplyDioRemoteDataSource(
    cookieStore: cookieStore ?? CookieStore(),
    dio: dio,
  );
}

class _ReplyRemoteTestAdapter implements HttpClientAdapter {
  _ReplyRemoteTestAdapter({
    required this.responseJson,
    this.responseHeaders = const <String, List<String>>{},
  });

  final Map<String, dynamic> responseJson;
  final Map<String, List<String>> responseHeaders;
  Uri lastUri = Uri();
  Map<String, dynamic> lastHeaders = <String, dynamic>{};
  String lastBody = '';

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUri = options.uri;
    lastHeaders = Map<String, dynamic>.from(options.headers);
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final bytes = <int>[];
      for (final chunk in chunks) {
        bytes.addAll(chunk);
      }
      lastBody = utf8.decode(bytes, allowMalformed: true);
    }

    return ResponseBody.fromString(
      jsonEncode(responseJson),
      200,
      headers: responseHeaders,
    );
  }
}
