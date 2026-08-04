import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/waf/waf.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/network/yamibo/yamibo_session_extractor.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YamiboHttpGateway', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
      'injects a browser User-Agent fallback when the caller omits one',
      () async {
        final adapter = _GatewayTestAdapter(textBody: '{}');
        final gateway = _buildGateway(adapter: adapter);

        await gateway.getJson(
          Uri.parse(
            'https://bbs.yamibo.com/api/mobile/index.php?module=profile',
          ),
          context: const YamiboRequestContext(
            kind: YamiboRequestKind.api,
            operation: 'profile',
            module: 'profile',
          ),
        );

        final ua = adapter.lastHeaders['User-Agent'] as String?;
        expect(ua, isNotNull);
        expect(ua, contains('Mozilla/5.0'));
      },
    );

    test('does not override a caller-supplied User-Agent', () async {
      final adapter = _GatewayTestAdapter(textBody: 'ok');
      final gateway = _buildGateway(adapter: adapter);

      await gateway.getText(
        Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.html,
          operation: 'forum.home.html',
        ),
        headers: const <String, String>{'User-Agent': 'CustomAgent/1.0'},
      );

      expect(adapter.lastHeaders['User-Agent'], 'CustomAgent/1.0');
    });

    test(
      'getText attaches cookies, saves set-cookie, and logs string length',
      () async {
        final adapter = _GatewayTestAdapter(
          textBody: '<html>ok</html>',
          setCookie: const <String>['auth=after; Path=/; HttpOnly'],
        );
        final logOutput = _MemoryLogOutput();
        final cookieStore = CookieStore();
        final uri = Uri.parse('https://bbs.yamibo.com/index.php?mobile=2');
        await cookieStore.saveFromSetCookie(uri, const <String>[
          'auth=before; Path=/; HttpOnly',
        ]);

        final gateway = _buildGateway(
          adapter: adapter,
          cookieStore: cookieStore,
          logOutput: logOutput,
        );

        final result = await gateway.getText(
          uri,
          context: const YamiboRequestContext(
            kind: YamiboRequestKind.html,
            operation: 'forum.home.chrome',
          ),
        );

        expect(
          result.isSuccess,
          isTrue,
          reason: '${result.errorOrNull?.message} ${result.errorOrNull?.raw}',
        );
        expect(result.dataOrNull?.body, '<html>ok</html>');
        expect(adapter.lastHeaders['Cookie'], 'auth=before');
        expect(await cookieStore.readCookieHeader(uri), 'auth=after');
        expect(
          logOutput.lines.join('\n'),
          contains(
            '[YamiboHTTP][html][forum.home.chrome] GET '
            'https://bbs.yamibo.com/index.php?mobile=2 -> 200',
          ),
        );
        expect(logOutput.lines.join('\n'), contains('requestId=yhttp-1'));
        expect(logOutput.lines.join('\n'), contains('body=String(length=15)'));
      },
    );

    test('getBytes logs imageProbe context and bytes length', () async {
      final adapter = _GatewayTestAdapter(bytesBody: const <int>[1, 2, 3, 4]);
      final logOutput = _MemoryLogOutput();
      final gateway = _buildGateway(adapter: adapter, logOutput: logOutput);

      final result = await gateway.getBytes(
        Uri.parse('https://bbs.yamibo.com/data/attachment/block/banner.jpg'),
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.imageProbe,
          operation: 'forum.home.carouselProbe',
          module: 'forum',
          pageKind: 'home',
        ),
      );

      expect(
        result.isSuccess,
        isTrue,
        reason: '${result.errorOrNull?.message} ${result.errorOrNull?.raw}',
      );
      expect(result.dataOrNull?.body, const <int>[1, 2, 3, 4]);
      expect(
        logOutput.lines.join('\n'),
        contains('[YamiboHTTP][imageProbe][forum.home.carouselProbe] GET'),
      );
      expect(logOutput.lines.join('\n'), contains('requestId=yhttp-1'));
      expect(logOutput.lines.join('\n'), contains('body=Bytes(length=4)'));
    });

    test('postFormFields preserves duplicate form field names', () async {
      final adapter = _GatewayTestAdapter(textBody: 'ok');
      final gateway = _buildGateway(adapter: adapter);

      final result = await gateway.postFormFields(
        Uri.parse('https://bbs.yamibo.com/forum.php?mod=misc&action=votepoll'),
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.html,
          operation: 'thread.poll.vote',
        ),
        data: const <MapEntry<String, String>>[
          MapEntry<String, String>('formhash', 'fh_poll'),
          MapEntry<String, String>('pollanswers[]', '1'),
          MapEntry<String, String>('pollanswers[]', '2'),
        ],
      );

      expect(result.isSuccess, isTrue);
      expect(
        adapter.lastRequestBody,
        'formhash=fh_poll&pollanswers%5B%5D=1&pollanswers%5B%5D=2',
      );
      expect(adapter.lastHeaders[Headers.contentTypeHeader], contains('form'));
    });

    test('getText failure keeps statusCode and logs the failure', () async {
      final adapter = _GatewayTestAdapter(statusCode: 503, textBody: 'down');
      final logOutput = _MemoryLogOutput();
      final gateway = _buildGateway(adapter: adapter, logOutput: logOutput);

      final result = await gateway.getText(
        Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.html,
          operation: 'forum.home.chrome',
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.statusCode, 503);
      expect(logOutput.lines.join('\n'), contains('-> failed 503'));
      expect(logOutput.lines.join('\n'), contains('requestId=yhttp-1'));
    });

    test(
      'runs foreground recovery and retries an explicit script challenge',
      () async {
        final adapter = _GatewayTestAdapter.scripted(const <_ScriptedResponse>[
          _ScriptedResponse(
            textBody:
                "<html><script>var arg1='ABC';document.cookie="
                "'acw_sc__v2=pass';</script></html>",
          ),
          _ScriptedResponse(textBody: '<html>forum home</html>'),
        ]);
        final coordinator = WafChallengeRecoveryCoordinator(
          retryCooldown: Duration.zero,
        );
        var launchCount = 0;
        coordinator.attachLauncher((request) async {
          launchCount += 1;
          expect(request.evidence, WafChallengeEvidence.scriptBody);
          expect(request.userAgent, BrowserUserAgents.mobile);
          return WafChallengeRecoveryResult.verified;
        });
        final gateway = _buildGateway(
          adapter: adapter,
          wafChallengeRecoveryCoordinator: coordinator,
        );

        final result = await gateway.getText(
          Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
          context: const YamiboRequestContext(
            kind: YamiboRequestKind.html,
            operation: 'forum.home.html',
          ),
        );

        expect(result.dataOrNull?.body, '<html>forum home</html>');
        expect(adapter.fetchCount, 2);
        expect(launchCount, 1);
      },
    );

    test('treats a GET 405 as a one-time suspected challenge', () async {
      final adapter = _GatewayTestAdapter.scripted(const <_ScriptedResponse>[
        _ScriptedResponse(statusCode: 405, textBody: 'Method Not Allowed'),
        _ScriptedResponse(textBody: '<html>recovered</html>'),
      ]);
      final coordinator =
          WafChallengeRecoveryCoordinator(
            retryCooldown: Duration.zero,
          )..attachLauncher((request) async {
            expect(request.evidence, WafChallengeEvidence.httpMethodNotAllowed);
            return WafChallengeRecoveryResult.verified;
          });
      final gateway = _buildGateway(
        adapter: adapter,
        wafChallengeRecoveryCoordinator: coordinator,
      );

      final result = await gateway.getText(
        Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.html,
          operation: 'forum.home.html',
        ),
      );

      expect(result.dataOrNull?.body, '<html>recovered</html>');
      expect(adapter.fetchCount, 2);
    });

    test(
      'native clearance probe classifies a WAF 405 without opening recovery',
      () async {
        final adapter = _GatewayTestAdapter(
          statusCode: 405,
          textBody: 'Method Not Allowed',
        );
        final coordinator = WafChallengeRecoveryCoordinator(
          retryCooldown: Duration.zero,
        );
        var launchCount = 0;
        coordinator.attachLauncher((_) async {
          launchCount += 1;
          return WafChallengeRecoveryResult.verified;
        });
        final gateway = _buildGateway(
          adapter: adapter,
          wafChallengeRecoveryCoordinator: coordinator,
        );

        final result = await gateway.probeWafChallengeClearance(
          Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
          userAgent: 'probe-agent',
        );

        expect(result, WafChallengeClearance.challenged);
        expect(adapter.fetchCount, 1);
        expect(launchCount, 0);
        expect(adapter.lastHeaders['User-Agent'], 'probe-agent');
      },
    );

    test(
      'native clearance probe accepts normal HTML and preserves cookies',
      () async {
        final cookieStore = CookieStore();
        final uri = Uri.parse('https://bbs.yamibo.com/index.php?mobile=2');
        await cookieStore.saveCookies(uri, const <String, String>{
          'EeqY_2132_auth': 'confirmed-auth',
        });
        final adapter = _GatewayTestAdapter(
          textBody: '<html><body>forum home</body></html>',
          setCookie: <String>['acw_sc__v2=probe-pass; Path=/'],
        );
        final gateway = _buildGateway(
          adapter: adapter,
          cookieStore: cookieStore,
        );

        final result = await gateway.probeWafChallengeClearance(
          uri,
          userAgent: 'probe-agent',
        );

        expect(result, WafChallengeClearance.cleared);
        expect(adapter.lastHeaders['Cookie'], contains('confirmed-auth'));
        expect(adapter.lastHeaders['User-Agent'], 'probe-agent');
        expect(
          await cookieStore.readCookieMap(uri),
          containsPair('EeqY_2132_auth', 'confirmed-auth'),
        );
        expect(
          await cookieStore.readCookieMap(uri),
          isNot(contains('acw_sc__v2')),
        );
      },
    );

    test(
      'native clearance probe rejects a non-empty challenge document',
      () async {
        final adapter = _GatewayTestAdapter(
          textBody:
              "<html><script>var arg1='ABC';document.cookie='acw_sc__v2=x';"
              '</script></html>',
        );
        final gateway = _buildGateway(adapter: adapter);

        final result = await gateway.probeWafChallengeClearance(
          Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
          userAgent: 'probe-agent',
        );

        expect(result, WafChallengeClearance.challenged);
      },
    );

    test(
      'native clearance probe treats server errors as inconclusive',
      () async {
        final gateway = _buildGateway(
          adapter: _GatewayTestAdapter(statusCode: 503, textBody: 'down'),
        );

        final result = await gateway.probeWafChallengeClearance(
          Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
          userAgent: 'probe-agent',
        );

        expect(result, WafChallengeClearance.inconclusive);
      },
    );

    test('does not recover or replay an ordinary POST 405', () async {
      final adapter = _GatewayTestAdapter(
        statusCode: 405,
        textBody: 'Method Not Allowed',
      );
      final coordinator = WafChallengeRecoveryCoordinator(
        retryCooldown: Duration.zero,
      );
      var launchCount = 0;
      coordinator.attachLauncher((_) async {
        launchCount += 1;
        return WafChallengeRecoveryResult.verified;
      });
      final gateway = _buildGateway(
        adapter: adapter,
        wafChallengeRecoveryCoordinator: coordinator,
      );

      final result = await gateway.postForm(
        Uri.parse('https://bbs.yamibo.com/forum.php?mod=example'),
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.html,
          operation: 'example.post',
        ),
        data: const <String, String>{'value': '1'},
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.statusCode, 405);
      expect(adapter.fetchCount, 1);
      expect(launchCount, 0);
    });

    test(
      'does not loop when the retried request is still challenged',
      () async {
        final adapter = _GatewayTestAdapter(
          textBody: "<html><script>var arg1='ABC';</script></html>",
        );
        final coordinator = WafChallengeRecoveryCoordinator(
          retryCooldown: Duration.zero,
        );
        var launchCount = 0;
        coordinator.attachLauncher((_) async {
          launchCount += 1;
          return WafChallengeRecoveryResult.verified;
        });
        final gateway = _buildGateway(
          adapter: adapter,
          wafChallengeRecoveryCoordinator: coordinator,
        );

        final result = await gateway.getText(
          Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
          context: const YamiboRequestContext(
            kind: YamiboRequestKind.html,
            operation: 'forum.home.html',
          ),
        );

        expect(result.isFailure, isTrue);
        expect(result.errorOrNull?.code, 'security_challenge_persisted');
        expect(adapter.fetchCount, 2);
        expect(launchCount, 1);
      },
    );

    test('challenge responses cannot delete an existing auth cookie', () async {
      final uri = Uri.parse('https://bbs.yamibo.com/index.php?mobile=2');
      final cookieStore = CookieStore();
      await cookieStore.saveCookies(uri, const <String, String>{
        'EeqY_2132_auth': 'confirmed-auth',
      });
      final adapter = _GatewayTestAdapter.scripted(const <_ScriptedResponse>[
        _ScriptedResponse(
          textBody: "<html><script>var arg1='ABC';</script></html>",
          setCookie: <String>['EeqY_2132_auth=deleted; Max-Age=0; Path=/'],
        ),
        _ScriptedResponse(textBody: '<html>recovered</html>'),
      ]);
      final coordinator = WafChallengeRecoveryCoordinator(
        retryCooldown: Duration.zero,
      )..attachLauncher((_) async => WafChallengeRecoveryResult.verified);
      final gateway = _buildGateway(
        adapter: adapter,
        cookieStore: cookieStore,
        wafChallengeRecoveryCoordinator: coordinator,
      );

      final result = await gateway.getText(
        uri,
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.html,
          operation: 'forum.home.html',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(
        await cookieStore.readCookieMap(uri),
        containsPair('EeqY_2132_auth', 'confirmed-auth'),
      );
      expect(adapter.lastHeaders['Cookie'], contains('confirmed-auth'));
    });

    test('getText stores session snapshot extracted from HTML', () async {
      final sessionStore = YamiboSessionStore();
      final gateway = _buildGateway(
        adapter: _GatewayTestAdapter(
          textBody: '''
<html>
  <body>
    <input type="hidden" name="formhash" value="fh_html">
    <script>var discuz_uid = '597454';</script>
  </body>
</html>
''',
        ),
        sessionStore: sessionStore,
        sessionExtractor: const YamiboSessionExtractor(),
      );

      final result = await gateway.getText(
        Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.html,
          operation: 'forum.home.html',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(sessionStore.readCurrent()?.uid, '597454');
      expect(sessionStore.readFreshFormhash(), 'fh_html');
      expect(sessionStore.readCurrent()?.source, 'html:forum.home.html');
    });

    test(
      'getJson stores session snapshot extracted from API variables',
      () async {
        final sessionStore = YamiboSessionStore();
        final gateway = _buildGateway(
          adapter: _GatewayTestAdapter(
            textBody: '''
{
  "Version": "4",
  "Charset": "utf-8",
  "Variables": {
    "formhash": "fh_api",
    "member_uid": "597454",
    "member_username": "tester"
  }
}
''',
          ),
          sessionStore: sessionStore,
          sessionExtractor: const YamiboSessionExtractor(),
        );

        final result = await gateway.getJson(
          Uri.parse(
            'https://bbs.yamibo.com/api/mobile/index.php?module=profile&version=4',
          ),
          context: const YamiboRequestContext(
            kind: YamiboRequestKind.api,
            operation: 'profile',
            module: 'profile',
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(sessionStore.readCurrent()?.uid, '597454');
        expect(sessionStore.readCurrent()?.username, 'tester');
        expect(sessionStore.readFreshFormhash(), 'fh_api');
        expect(sessionStore.readCurrent()?.source, 'api:profile');
      },
    );
  });
}

YamiboHttpGateway _buildGateway({
  required _GatewayTestAdapter adapter,
  CookieStore? cookieStore,
  _MemoryLogOutput? logOutput,
  YamiboSessionStore? sessionStore,
  YamiboSessionExtractor? sessionExtractor,
  WafChallengeRecoveryCoordinator? wafChallengeRecoveryCoordinator,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return YamiboHttpGateway(
    cookieStore: cookieStore ?? CookieStore(),
    logger: Logger(
      printer: SimplePrinter(colors: false),
      output: logOutput ?? _MemoryLogOutput(),
      filter: ProductionFilter(),
      level: Level.trace,
    ),
    sessionStore: sessionStore,
    sessionExtractor: sessionExtractor,
    wafChallengeRecoveryCoordinator: wafChallengeRecoveryCoordinator,
    dio: dio,
  );
}

class _ScriptedResponse {
  const _ScriptedResponse({
    this.statusCode = 200,
    this.textBody = '',
    this.bytesBody = const <int>[],
    this.setCookie = const <String>[],
  });

  final int statusCode;
  final String textBody;
  final List<int> bytesBody;
  final List<String> setCookie;
}

class _GatewayTestAdapter implements HttpClientAdapter {
  /// Single-response ctor kept for existing tests: emits [textBody]/[bytesBody]
  /// on every fetch call.
  _GatewayTestAdapter({
    int statusCode = 200,
    String textBody = '',
    List<int> bytesBody = const <int>[],
    List<String> setCookie = const <String>[],
  }) : _responses = <_ScriptedResponse>[
         _ScriptedResponse(
           statusCode: statusCode,
           textBody: textBody,
           bytesBody: bytesBody,
           setCookie: setCookie,
         ),
       ],
       _replayLastForever = true;

  _GatewayTestAdapter.scripted(List<_ScriptedResponse> responses)
    : assert(responses.isNotEmpty),
      _responses = List<_ScriptedResponse>.of(responses),
      _replayLastForever = false;

  final List<_ScriptedResponse> _responses;
  final bool _replayLastForever;
  int fetchCount = 0;
  Map<String, dynamic> lastHeaders = const <String, dynamic>{};
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
    lastRequestBody = await _readRequestBody(requestStream);
    final index = fetchCount;
    fetchCount += 1;
    final scripted = index < _responses.length
        ? _responses[index]
        : (_replayLastForever
              ? _responses.last
              : throw StateError('No more scripted responses'));
    final headers = scripted.setCookie.isEmpty
        ? const <String, List<String>>{}
        : <String, List<String>>{'set-cookie': scripted.setCookie};
    if (options.responseType == ResponseType.bytes) {
      return ResponseBody.fromBytes(
        scripted.bytesBody,
        scripted.statusCode,
        headers: headers,
      );
    }
    final responseHeaders = switch (options.responseType) {
      ResponseType.json => <String, List<String>>{
        ...headers,
        Headers.contentTypeHeader: const <String>['application/json'],
      },
      ResponseType.plain => <String, List<String>>{
        ...headers,
        Headers.contentTypeHeader: const <String>['text/html; charset=utf-8'],
      },
      _ => headers,
    };
    return ResponseBody.fromString(
      scripted.textBody,
      scripted.statusCode,
      headers: responseHeaders,
    );
  }

  Future<String?> _readRequestBody(Stream<Uint8List>? requestStream) async {
    if (requestStream == null) {
      return null;
    }
    final bytes = await requestStream.expand((chunk) => chunk).toList();
    if (bytes.isEmpty) {
      return '';
    }
    return String.fromCharCodes(bytes);
  }
}

class _MemoryLogOutput extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) {
    lines.addAll(event.lines);
  }
}
