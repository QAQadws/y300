import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/posting/data/new_thread_remote_data_source.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiscuzNewThreadDioRemoteDataSource', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('posts newthread with expected query, body and referer', () async {
      final adapter = _Adapter(
        responseJson: <String, dynamic>{
          'Variables': <String, dynamic>{
            'tid': '999001',
            'pid': '888001',
          },
          'Message': <String, dynamic>{
            'messageval': 'post_newthread_succeed',
            'messagestr': '主题已发布',
          },
        },
      );
      final dataSource = _build(adapter);

      final response = await dataSource.submit(
        const NewThreadSubmitForm(
          payload: NewThreadDraftPayload(
            fid: '33',
            formHash: 'fh',
            subject: '测试标题',
            message: '测试正文',
            typeid: '101',
            useSignature: true,
            allowNoticeAuthor: false,
            bbCodeOff: false,
            smileyOff: false,
            parseUrlOff: false,
          ),
        ),
      );

      expect(response.statusCode, 200);
      expect(adapter.lastUri.queryParameters['module'], 'newthread');
      expect(adapter.lastUri.queryParameters['version'], '4');
      expect(adapter.lastUri.queryParameters['fid'], '33');
      expect(
        adapter.lastHeaders['referer'],
        contains('mod=post&action=newthread&fid=33'),
      );
      expect(adapter.lastBody, contains('formhash=fh'));
      expect(adapter.lastBody, contains('topicsubmit=yes'));
      expect(adapter.lastBody, contains('typeid=101'));
      // 中文经过 form-urlencoded 编码（utf-8 % 编码）。
      expect(adapter.lastBody, contains('subject='));
      expect(adapter.lastBody, contains('special=0'));
      expect(adapter.lastBody, contains('usesig=1'));
      expect(adapter.lastBody, contains('allownoticeauthor=0'));
      // tags / poll 都没设置 → form 里不应出现这些键。
      expect(adapter.lastBody, isNot(contains('tags=')));
      expect(adapter.lastBody, isNot(contains('tpolloption=')));
      expect(adapter.lastBody, isNot(contains('polloptions=')));
    });

    test('serializes tags as joined comma string when non-empty', () async {
      final adapter = _Adapter(
        responseJson: <String, dynamic>{
          'Variables': <String, dynamic>{'tid': '1', 'pid': '2'},
          'Message': <String, dynamic>{'messageval': 'post_newthread_succeed'},
        },
      );
      final dataSource = _build(adapter);

      await dataSource.submit(
        const NewThreadSubmitForm(
          payload: NewThreadDraftPayload(
            fid: '33',
            formHash: 'fh',
            subject: 't',
            message: 'm',
            typeid: '0',
            useSignature: false,
            allowNoticeAuthor: false,
            bbCodeOff: false,
            smileyOff: false,
            parseUrlOff: false,
            tags: ['a', 'b'],
          ),
        ),
      );

      expect(adapter.lastBody, contains('tags=a%2Cb'));
    });

    test('serializes poll fields when special=poll', () async {
      final adapter = _Adapter(
        responseJson: <String, dynamic>{
          'Variables': <String, dynamic>{'tid': '1', 'pid': '2'},
          'Message': <String, dynamic>{'messageval': 'post_newthread_succeed'},
        },
      );
      final dataSource = _build(adapter);

      await dataSource.submit(
        const NewThreadSubmitForm(
          payload: NewThreadDraftPayload(
            fid: '33',
            formHash: 'fh',
            subject: '投票',
            message: '说明',
            typeid: '0',
            useSignature: true,
            allowNoticeAuthor: false,
            bbCodeOff: false,
            smileyOff: false,
            parseUrlOff: false,
            special: NewThreadSpecial.poll,
            poll: NewThreadPollDraft(
              options: ['A', 'B', 'C'],
              multiple: true,
              maxChoices: 2,
              expirationDays: 7,
              overt: true,
              visibilityPoll: true,
            ),
          ),
        ),
      );

      expect(adapter.lastBody, contains('special=1'));
      expect(adapter.lastBody, contains('tpolloption=2'));
      // polloptions 用 \n 分隔；form 编码后是 %0A。
      expect(adapter.lastBody, contains('polloptions=A%0AB%0AC'));
      expect(adapter.lastBody, contains('maxchoices=2'));
      expect(adapter.lastBody, contains('expiration=7'));
      expect(adapter.lastBody, contains('overt=1'));
      expect(adapter.lastBody, contains('visibilitypoll=1'));
    });

    test('single-choice poll caps maxchoices at 1 regardless of stored value',
        () async {
      final adapter = _Adapter(
        responseJson: <String, dynamic>{
          'Variables': <String, dynamic>{'tid': '1', 'pid': '2'},
          'Message': <String, dynamic>{'messageval': 'post_newthread_succeed'},
        },
      );
      final dataSource = _build(adapter);

      await dataSource.submit(
        const NewThreadSubmitForm(
          payload: NewThreadDraftPayload(
            fid: '33',
            formHash: 'fh',
            subject: '投票',
            message: '说明',
            typeid: '0',
            useSignature: false,
            allowNoticeAuthor: false,
            bbCodeOff: false,
            smileyOff: false,
            parseUrlOff: false,
            special: NewThreadSpecial.poll,
            poll: NewThreadPollDraft(
              options: ['A', 'B'],
              multiple: false,
              maxChoices: 5,
              expirationDays: 0,
            ),
          ),
        ),
      );

      expect(adapter.lastBody, contains('maxchoices=1'));
      expect(adapter.lastBody, contains('expiration=0'));
      expect(adapter.lastBody, isNot(contains('visibilitypoll=')));
    });
  });
}

DiscuzNewThreadDioRemoteDataSource _build(_Adapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return DiscuzNewThreadDioRemoteDataSource(
    gateway: YamiboHttpGateway(
      cookieStore: CookieStore(),
      logger: Logger(level: Level.off),
      dio: dio,
      enableLog: false,
    ),
  );
}

class _Adapter implements HttpClientAdapter {
  _Adapter({required this.responseJson});

  final Map<String, dynamic> responseJson;
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
      headers: const <String, List<String>>{},
    );
  }
}
