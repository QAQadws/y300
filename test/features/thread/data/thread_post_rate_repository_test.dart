import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/thread/data/thread_post_rate_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ThreadPostRateFormParser', () {
    test('parses desktop rate dialog form', () {
      final html = File('docs/html/帖子详细页/一个楼的评分功能.html').readAsStringSync();
      const parser = ThreadPostRateFormParser();

      final form = parser.parse(
        html,
        fallbackRateUrl:
            'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=572529&pid=41562047',
      );

      expect(form.actionUrl, contains('ratesubmit=yes'));
      expect(form.formHash, 'cba80c43');
      expect(form.tid, '572529');
      expect(form.pid, '41562047');
      expect(form.referer, contains('viewthread'));
      expect(form.scoreName, 'score1');
      expect(form.scoreMin, 0);
      expect(form.scoreMax, 5);
      expect(form.todayRemaining, 10);
      expect(form.defaultScore, 5);
      expect(form.reasonOptions, <String>[
        '你太可爱',
        '好萌好萌好萌',
        '我很赞同',
        '精品文章',
        '原创内容',
      ]);
      expect(form.notifyAuthorDefault, isFalse);
    });

    test('parses cdata wrapped desktop rate dialog form', () {
      const html = '''
<root>
<![CDATA[ <div class="tm_c" id="floatlayout_topicadmin"> <h3 class="flb"> <em id="return_rate">评分</em> </h3> <form id="rateform" method="post" autocomplete="off" action="forum.php?mod=misc&amp;action=rate&amp;ratesubmit=yes&amp;infloat=yes"> <input type="hidden" name="formhash" value="cba80c43" /> <input type="hidden" name="tid" value="560713" /> <input type="hidden" name="pid" value="41312932" /> <input type="hidden" name="referer" value="https://bbs.yamibo.com/forum.php?mod=viewthread&tid=560713&page=0#pid41312932" /> <input type="hidden" name="handlekey" value="rate"><div class="c"> <table cellspacing="0" cellpadding="0" class="dt mbm"> <tr> <th>&nbsp;</th> <th width="65">&nbsp;</th> <th width="65">评分区间</th> <th width="55">今日剩余</th> </tr><tr> <td> 积分</td> <td> <input type="text" name="score1" id="score1" class="px z" value="0" style="width: 25px;" /> <a href="javascript:;" class="dpbtn" onclick="showselect(this, 'score1', 'scoreoption1')">^</a> <ul id="scoreoption1" style="display:none"><li>+5</li><li>+4</li><li>+3</li><li>+2</li><li>+1</li></ul> </td> <td>0 ~ 5</td><td>10</td> </tr> </table> <div class="tpclg"> <h4>可选评分理由:</h4> <table cellspacing="0" cellpadding="0" class="reason_slct"> <tr> <td> <ul id="reasonselect" class="reasonselect pt"><li>你太可爱</li><li>好萌好萌好萌</li><li>我很赞同</li><li>精品文章</li><li>原创内容</li></ul> </td> </tr> <tr> <td><input type="text" name="reason" id="reason" class="px" /></td> </tr> </table> </div> </div> <p class="o pns"> <label for="sendreasonpm"><input type="checkbox" name="sendreasonpm" id="sendreasonpm" class="pc" />通知作者</label> <button name="ratesubmit" type="submit" value="true" class="pn pnc"><span>确定</span></button> </p> </form> </div> ]]>
</root>
''';
      const parser = ThreadPostRateFormParser();

      final form = parser.parse(
        html,
        fallbackRateUrl:
            'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&ratesubmit=yes',
      );

      expect(form.formHash, 'cba80c43');
      expect(form.tid, '560713');
      expect(form.pid, '41312932');
      expect(form.scoreMax, 5);
      expect(form.todayRemaining, 10);
      expect(form.reasonOptions, contains('我很赞同'));
    });

    test('builds fallback form from rate url and session formhash', () {
      const builder = ThreadPostRateFormFallbackBuilder();

      final form = builder.build(
        seed: const ThreadPostRateFormSeed(
          rateUrl:
              'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=572529&pid=41562047',
          tid: '572529',
          pid: '41562047',
          referer:
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=572529#pid41562047',
        ),
        formHash: 'cba80c43',
      );

      expect(form, isNotNull);
      expect(form!.actionUrl, contains('ratesubmit=yes'));
      expect(form.formHash, 'cba80c43');
      expect(form.tid, '572529');
      expect(form.pid, '41562047');
      expect(form.referer, contains('#pid41562047'));
      expect(form.scoreName, 'score1');
      expect(form.scoreMin, 0);
      expect(form.scoreMax, 5);
      expect(form.defaultScore, 5);
      expect(form.todayRemaining, 0);
      expect(
        form.reasonOptions,
        ThreadPostRateFormFallbackBuilder.defaultReasonOptions,
      );
    });

    test('does not build fallback without formhash', () {
      const builder = ThreadPostRateFormFallbackBuilder();

      final form = builder.build(
        seed: const ThreadPostRateFormSeed(
          rateUrl:
              'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=572529&pid=41562047',
          tid: '572529',
          pid: '41562047',
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
          uid: '597454',
          username: 'tester',
          formhash: 'fh_rate',
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
        'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=572529&pid=41562047',
      );

      expect(result.isSuccess, isTrue);
      final form = result.dataOrNull!;
      expect(form.formHash, 'fh_rate');
      expect(form.tid, '572529');
      expect(form.pid, '41562047');
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
              'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=572529&pid=41562047',
          tid: '572529',
          pid: '41562047',
          referer: '',
        ),
        formHash: 'fh_rate',
      )!;

      final result = await repository.submit(
        ThreadPostRateDraft(
          form: form,
          score: 5,
          reason: '我很赞同',
          notifyAuthor: true,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(adapter.lastRequestBody, contains('formhash=fh_rate'));
      expect(adapter.lastRequestBody, contains('tid=572529'));
      expect(adapter.lastRequestBody, contains('pid=41562047'));
      expect(adapter.lastRequestBody, contains('score1=5'));
      expect(adapter.lastRequestBody, contains('reason='));
      expect(adapter.lastRequestBody, contains('sendreasonpm=on'));
      expect(adapter.lastRequestBody, contains('ratesubmit=true'));
      expect(adapter.lastHeaders['referer'], contains('tid=572529'));
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
              'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=572529&pid=41562047',
          tid: '572529',
          pid: '41562047',
          referer: '',
        ),
        formHash: 'fh_rate',
      )!;

      final result = await repository.submit(
        ThreadPostRateDraft(
          form: form,
          score: 5,
          reason: '我很赞同',
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
