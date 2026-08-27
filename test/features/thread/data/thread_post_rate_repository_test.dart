import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/thread/data/repositories/thread_post_rate_repository.dart';

import '../../../test_support/utf8_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ThreadPostRateFormParser', () {
    test('parses desktop rate dialog form', () {
      final html = readUtf8TestFixture('thread/actions/rate_form.html');
      const parser = ThreadPostRateFormParser();

      final form = parser.parse(
        html,
        fallbackRateUrl:
            'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=10001&pid=20001',
      );

      expect(form.actionUrl, contains('ratesubmit=yes'));
      expect(form.formHash, 'fixture-formhash');
      expect(form.tid, '10001');
      expect(form.pid, '20001');
      expect(form.referer, contains('viewthread'));
      expect(form.scoreName, 'score1');
      expect(form.scoreMin, 0);
      expect(form.scoreMax, 5);
      expect(form.todayRemaining, 10);
      expect(form.defaultScore, 5);
      expect(form.reasonOptions, <String>['测试理由一', '测试理由二', '测试理由三']);
      expect(form.reasonOrigin, ThreadPostRateReasonOrigin.serverForm);
      expect(form.notifyAuthorDefault, isFalse);
    });

    test('parses cdata wrapped desktop rate dialog form', () {
      const html = '''
<root>
<![CDATA[
<form id="rateform" action="forum.php?mod=misc&amp;action=rate&amp;ratesubmit=yes">
  <input name="formhash" value="fixture-formhash">
  <input name="tid" value="10001">
  <input name="pid" value="20001">
  <input name="referer" value="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=10001#pid20001">
  <table><tr><td>测试积分</td><td><input name="score1" value="0"></td><td>0 ~ 5</td><td>10</td></tr></table>
  <ul id="reasonselect"><li>测试理由一</li></ul>
</form>
]]>
</root>
''';
      const parser = ThreadPostRateFormParser();

      final form = parser.parse(
        html,
        fallbackRateUrl:
            'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&ratesubmit=yes',
      );

      expect(form.formHash, 'fixture-formhash');
      expect(form.tid, '10001');
      expect(form.pid, '20001');
      expect(form.scoreMax, 5);
      expect(form.todayRemaining, 10);
      expect(form.reasonOptions, contains('测试理由一'));
    });

    test('builds fallback form from rate url and session formhash', () {
      const builder = ThreadPostRateFormFallbackBuilder();

      final form = builder.build(
        seed: const ThreadPostRateFormSeed(
          rateUrl:
              'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=10001&pid=20001',
          tid: '10001',
          pid: '20001',
          referer:
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10001#pid20001',
        ),
        formHash: 'fixture-formhash',
      );

      expect(form, isNotNull);
      expect(form!.actionUrl, contains('ratesubmit=yes'));
      expect(form.formHash, 'fixture-formhash');
      expect(form.tid, '10001');
      expect(form.pid, '20001');
      expect(form.referer, contains('#pid20001'));
      expect(form.scoreName, 'score1');
      expect(form.scoreMin, 0);
      expect(form.scoreMax, 5);
      expect(form.defaultScore, 5);
      expect(form.todayRemaining, 0);
      expect(
        form.reasonOptions,
        ThreadPostRateFormFallbackBuilder.defaultReasonOptions,
      );
      expect(form.reasonOrigin, ThreadPostRateReasonOrigin.applicationFallback);
    });

    test('does not build fallback without formhash', () {
      const builder = ThreadPostRateFormFallbackBuilder();

      final form = builder.build(
        seed: const ThreadPostRateFormSeed(
          rateUrl:
              'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=10001&pid=20001',
          tid: '10001',
          pid: '20001',
          referer: '',
        ),
        formHash: null,
      );

      expect(form, isNull);
    });
  });

  group('DiscuzThreadPostRateRepository', () {
    test('falls back to local rate form when remote html misses form', () async {
      final sessionStore = YamiboSessionStore();
      sessionStore.saveExtracted(
        YamiboSessionSnapshot(
          isLoggedIn: true,
          uid: '30001',
          username: 'fixture-user',
          formhash: 'fixture-rate-formhash',
          updatedAt: DateTime.now(),
          source: 'api:profile',
        ),
      );
      final adapter = _RateFormTestAdapter(textBody: '<div>empty</div>');
      final repository = DiscuzThreadPostRateRepository(
        gateway: _buildGateway(adapter),
        sessionStore: sessionStore,
      );

      final result = await repository.loadForm(
        'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=10001&pid=20001',
      );

      expect(result.isSuccess, isTrue);
      final form = result.dataOrNull!;
      expect(form.formHash, 'fixture-rate-formhash');
      expect(form.tid, '10001');
      expect(form.pid, '20001');
      expect(
        form.reasonOptions,
        ThreadPostRateFormFallbackBuilder.defaultReasonOptions,
      );
      expect(adapter.lastUri?.queryParameters.containsKey('mobile'), isFalse);
      expect(adapter.lastUri?.queryParameters['infloat'], 'yes');
      expect(adapter.lastUri?.queryParameters['handlekey'], 'rate');
      expect(adapter.lastUri?.queryParameters['inajax'], '1');
      expect(adapter.lastHeaders['User-Agent'], contains('Windows NT 10.0'));
    });

    test('submits fallback form fields', () async {
      final adapter = _RateFormTestAdapter(
        textBody:
            '{"Message":{"messageval":"rate_succeed","messagestr":"评分成功"}}',
      );
      final repository = DiscuzThreadPostRateRepository(
        gateway: _buildGateway(adapter),
        sessionStore: YamiboSessionStore(),
      );
      final form = const ThreadPostRateFormFallbackBuilder().build(
        seed: const ThreadPostRateFormSeed(
          rateUrl:
              'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=10001&pid=20001',
          tid: '10001',
          pid: '20001',
          referer: '',
        ),
        formHash: 'fixture-rate-formhash',
      )!;

      final result = await repository.submit(
        ThreadPostRateDraft(
          form: form,
          score: 5,
          reason: '测试理由一',
          notifyAuthor: true,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(
        adapter.lastRequestBody,
        contains('formhash=fixture-rate-formhash'),
      );
      expect(adapter.lastRequestBody, contains('tid=10001'));
      expect(adapter.lastRequestBody, contains('pid=20001'));
      expect(adapter.lastRequestBody, contains('score1=5'));
      expect(adapter.lastRequestBody, contains('reason='));
      expect(adapter.lastRequestBody, contains('sendreasonpm=on'));
      expect(adapter.lastRequestBody, contains('ratesubmit=true'));
      expect(adapter.lastHeaders['referer'], contains('tid=10001'));
      expect(adapter.lastUri?.queryParameters['ratesubmit'], 'yes');
      expect(adapter.lastUri?.queryParameters['infloat'], 'yes');
      expect(adapter.lastUri?.queryParameters['inajax'], '1');
      expect(adapter.lastUri?.queryParameters['handlekey'], 'rateform');
    });

    test('parses cdata wrapped submit message', () async {
      final adapter = _RateFormTestAdapter(
        textBody:
            '<root><![CDATA[<div id="messagetext"><p>感谢您的参与，现在将转入评分前页面</p></div>]]></root>',
      );
      final repository = DiscuzThreadPostRateRepository(
        gateway: _buildGateway(adapter),
        sessionStore: YamiboSessionStore(),
      );
      final form = const ThreadPostRateFormFallbackBuilder().build(
        seed: const ThreadPostRateFormSeed(
          rateUrl:
              'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=10001&pid=20001',
          tid: '10001',
          pid: '20001',
          referer: '',
        ),
        formHash: 'fixture-rate-formhash',
      )!;

      final result = await repository.submit(
        ThreadPostRateDraft(
          form: form,
          score: 5,
          reason: '测试理由一',
          notifyAuthor: false,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.message, contains('感谢您的参与'));
    });
  });
}

YamiboHttpGateway _buildGateway(_RateFormTestAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return YamiboHttpGateway(
    cookieStore: CookieStore(),
    logger: Logger(
      printer: SimplePrinter(colors: false),
      output: _SilentLogOutput(),
      filter: ProductionFilter(),
    ),
    dio: dio,
    enableLog: false,
  );
}

class _RateFormTestAdapter implements HttpClientAdapter {
  _RateFormTestAdapter({required this.textBody});

  final String textBody;
  Map<String, dynamic> lastHeaders = const <String, dynamic>{};
  Uri? lastUri;
  String? lastRequestBody;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastHeaders = options.headers;
    lastUri = options.uri;
    lastRequestBody = await _readRequestBody(requestStream);
    return ResponseBody.fromString(
      textBody,
      200,
      headers: const <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      },
    );
  }

  Future<String?> _readRequestBody(Stream<Uint8List>? requestStream) async {
    if (requestStream == null) {
      return null;
    }
    final chunks = await requestStream.toList();
    final bytes = chunks.expand((chunk) => chunk).toList(growable: false);
    return String.fromCharCodes(bytes);
  }
}

class _SilentLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}
