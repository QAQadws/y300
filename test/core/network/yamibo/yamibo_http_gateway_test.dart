import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_diagnostic_recorder.dart';
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
      'getText attaches cookies, saves set-cookie, records diagnostics, and logs string length',
      () async {
        final adapter = _GatewayTestAdapter(
          textBody: '<html>ok</html>',
          setCookie: const <String>['auth=after; Path=/; HttpOnly'],
        );
        final diagnostics = _RecordingNetworkDiagnosticRecorder();
        final logOutput = _MemoryLogOutput();
        final cookieStore = CookieStore();
        final uri = Uri.parse('https://bbs.yamibo.com/index.php?mobile=2');
        await cookieStore.saveFromSetCookie(uri, const <String>[
          'auth=before; Path=/; HttpOnly',
        ]);

        final gateway = _buildGateway(
          adapter: adapter,
          cookieStore: cookieStore,
          diagnostics: diagnostics,
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
        expect(diagnostics.records.single.succeeded, isTrue);
        expect(diagnostics.records.single.statusCode, 200);
        expect(diagnostics.records.single.kind, 'html');
        expect(diagnostics.records.single.operation, 'forum.home.chrome');
        expect(diagnostics.records.single.requestId, 'yhttp-1');
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

    test('getBytes records imageProbe context and logs bytes length', () async {
      final adapter = _GatewayTestAdapter(bytesBody: const <int>[1, 2, 3, 4]);
      final diagnostics = _RecordingNetworkDiagnosticRecorder();
      final logOutput = _MemoryLogOutput();
      final gateway = _buildGateway(
        adapter: adapter,
        diagnostics: diagnostics,
        logOutput: logOutput,
      );

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
      expect(diagnostics.records.single.succeeded, isTrue);
      expect(diagnostics.records.single.kind, 'imageProbe');
      expect(diagnostics.records.single.operation, 'forum.home.carouselProbe');
      expect(diagnostics.records.single.module, 'forum');
      expect(diagnostics.records.single.pageKind, 'home');
      expect(diagnostics.records.single.requestId, 'yhttp-1');
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

    test(
      'getText failure keeps statusCode and records failed diagnostic',
      () async {
        final adapter = _GatewayTestAdapter(statusCode: 503, textBody: 'down');
        final diagnostics = _RecordingNetworkDiagnosticRecorder();
        final logOutput = _MemoryLogOutput();
        final gateway = _buildGateway(
          adapter: adapter,
          diagnostics: diagnostics,
          logOutput: logOutput,
        );

        final result = await gateway.getText(
          Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
          context: const YamiboRequestContext(
            kind: YamiboRequestKind.html,
            operation: 'forum.home.chrome',
          ),
        );

        expect(result.isFailure, isTrue);
        expect(result.errorOrNull?.statusCode, 503);
        expect(diagnostics.records.single.succeeded, isFalse);
        expect(diagnostics.records.single.statusCode, 503);
        expect(diagnostics.records.single.kind, 'html');
        expect(diagnostics.records.single.operation, 'forum.home.chrome');
        expect(diagnostics.records.single.requestId, 'yhttp-1');
        expect(logOutput.lines.join('\n'), contains('-> failed 503'));
        expect(logOutput.lines.join('\n'), contains('requestId=yhttp-1'));
      },
    );

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
  _RecordingNetworkDiagnosticRecorder? diagnostics,
  _MemoryLogOutput? logOutput,
  YamiboSessionStore? sessionStore,
  YamiboSessionExtractor? sessionExtractor,
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
    diagnosticRecorder: diagnostics,
    sessionStore: sessionStore,
    sessionExtractor: sessionExtractor,
    dio: dio,
  );
}

class _GatewayTestAdapter implements HttpClientAdapter {
  _GatewayTestAdapter({
    this.statusCode = 200,
    this.textBody = '',
    this.bytesBody = const <int>[],
    this.setCookie = const <String>[],
  });

  final int statusCode;
  final String textBody;
  final List<int> bytesBody;
  final List<String> setCookie;
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
    final headers = setCookie.isEmpty
        ? const <String, List<String>>{}
        : <String, List<String>>{'set-cookie': setCookie};
    if (options.responseType == ResponseType.bytes) {
      return ResponseBody.fromBytes(bytesBody, statusCode, headers: headers);
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
      textBody,
      statusCode,
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

class _RecordingNetworkDiagnosticRecorder implements NetworkDiagnosticRecorder {
  final records = <_DiagnosticRecord>[];

  @override
  void recordHttpRequest({
    required String method,
    required Uri uri,
    required DateTime startedAt,
    required int elapsedMs,
    int? statusCode,
    bool succeeded = true,
    String? error,
    String? kind,
    String? operation,
    String? module,
    String? pageKind,
    String? requestId,
  }) {
    records.add(
      _DiagnosticRecord(
        method: method,
        uri: uri,
        startedAt: startedAt,
        elapsedMs: elapsedMs,
        statusCode: statusCode,
        succeeded: succeeded,
        error: error,
        kind: kind,
        operation: operation,
        module: module,
        pageKind: pageKind,
        requestId: requestId,
      ),
    );
  }
}

class _DiagnosticRecord {
  const _DiagnosticRecord({
    required this.method,
    required this.uri,
    required this.startedAt,
    required this.elapsedMs,
    required this.succeeded,
    this.statusCode,
    this.error,
    this.kind,
    this.operation,
    this.module,
    this.pageKind,
    this.requestId,
  });

  final String method;
  final Uri uri;
  final DateTime startedAt;
  final int elapsedMs;
  final int? statusCode;
  final bool succeeded;
  final String? error;
  final String? kind;
  final String? operation;
  final String? module;
  final String? pageKind;
  final String? requestId;
}

class _MemoryLogOutput extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) {
    lines.addAll(event.lines);
  }
}
