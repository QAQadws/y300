import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_diagnostic_recorder.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YamiboHttpGateway', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('getText attaches cookies, saves set-cookie, records diagnostics, and logs string length', () async {
      final adapter = _GatewayTestAdapter(
        textBody: '<html>ok</html>',
        setCookie: const <String>['auth=after; Path=/; HttpOnly'],
      );
      final diagnostics = _RecordingNetworkDiagnosticRecorder();
      final logOutput = _MemoryLogOutput();
      final cookieStore = CookieStore();
      final uri = Uri.parse('https://bbs.yamibo.com/index.php?mobile=2');
      await cookieStore.saveFromSetCookie(
        uri,
        const <String>['auth=before; Path=/; HttpOnly'],
      );

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

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.body, '<html>ok</html>');
      expect(adapter.lastHeaders['Cookie'], 'auth=before');
      expect(await cookieStore.readCookieHeader(uri), 'auth=after');
      expect(diagnostics.records.single.succeeded, isTrue);
      expect(diagnostics.records.single.statusCode, 200);
      expect(
        logOutput.lines.join('\n'),
        contains(
          '[YamiboHTTP][html][forum.home.chrome] GET '
          'https://bbs.yamibo.com/index.php?mobile=2 -> 200',
        ),
      );
      expect(logOutput.lines.join('\n'), contains('body=String(length=15)'));
    });

    test('getBytes records imageProbe context and logs bytes length', () async {
      final adapter = _GatewayTestAdapter(
        bytesBody: const <int>[1, 2, 3, 4],
      );
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
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.body, const <int>[1, 2, 3, 4]);
      expect(diagnostics.records.single.succeeded, isTrue);
      expect(
        logOutput.lines.join('\n'),
        contains('[YamiboHTTP][imageProbe][forum.home.carouselProbe] GET'),
      );
      expect(logOutput.lines.join('\n'), contains('body=Bytes(length=4)'));
    });

    test('getText failure keeps statusCode and records failed diagnostic', () async {
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
      expect(logOutput.lines.join('\n'), contains('-> failed 503'));
    });
  });
}

YamiboHttpGateway _buildGateway({
  required _GatewayTestAdapter adapter,
  CookieStore? cookieStore,
  _RecordingNetworkDiagnosticRecorder? diagnostics,
  _MemoryLogOutput? logOutput,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com',
      validateStatus: (status) => status != null && status >= 200 && status < 400,
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

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastHeaders = options.headers;
    final headers = setCookie.isEmpty
        ? const <String, List<String>>{}
        : <String, List<String>>{'set-cookie': setCookie};
    if (options.responseType == ResponseType.bytes) {
      return ResponseBody.fromBytes(bytesBody, statusCode, headers: headers);
    }
    return ResponseBody.fromString(textBody, statusCode, headers: headers);
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
  });

  final String method;
  final Uri uri;
  final DateTime startedAt;
  final int elapsedMs;
  final int? statusCode;
  final bool succeeded;
  final String? error;
}

class _MemoryLogOutput extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) {
    lines.addAll(event.lines);
  }
}
