import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  final site = Uri.parse('https://bbs.example.test');
  final signUri = Uri.parse(
    'https://bbs.example.test/plugin.php?id=zqlj_sign&sign=opaque-fixture-value',
  );

  test(
    'opaque sign GET never replays after a 405 or reaches the logger',
    () async {
      final http = _ScriptedHttpAdapter(<int>[405, 200]);
      final waf = _VerifiedWaf();
      final logger = _RecordingLogger();
      final network = DioForumClientNetwork(
        config: ForumClientConfig(siteOrigin: site, userAgent: 'fixture-agent'),
        cookies: MemoryForumCookieStore(),
        waf: waf,
        logger: logger,
        dio: Dio()..httpClientAdapter = http,
      );

      final result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: signUri,
          context: const ForumRequestContext(operation: 'daily_sign_in.submit'),
          followRedirects: false,
          allowWafReplay: false,
        ),
      );

      expect(result, isA<ForumTransportError<ForumResponse<Object?>>>());
      final failure =
          (result as ForumTransportError<ForumResponse<Object?>>).failure;
      expect(failure.statusCode, 405);
      expect(http.requests, 1);
      expect(http.followRedirects, <bool>[false]);
      expect(waf.calls, 0);
      expect(logger.uris.single.queryParameters['sign'], '[REDACTED]');
      expect(
        logger.uris.single.toString(),
        isNot(contains('opaque-fixture-value')),
      );
    },
  );

  test(
    'non-following sign response exposes redirect without a second GET',
    () async {
      final http = _ScriptedHttpAdapter(<int>[302]);
      final logger = _RecordingLogger();
      final network = DioForumClientNetwork(
        config: ForumClientConfig(siteOrigin: site, userAgent: 'fixture-agent'),
        cookies: MemoryForumCookieStore(),
        logger: logger,
        dio: Dio()..httpClientAdapter = http,
      );

      final result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: signUri,
          context: const ForumRequestContext(operation: 'daily_sign_in.submit'),
          followRedirects: false,
          allowWafReplay: false,
        ),
      );

      expect(result, isA<ForumTransportSuccess<ForumResponse<Object?>>>());
      final response =
          (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
      expect(response.statusCode, 302);
      expect(response.uri, signUri);
      expect(http.requests, 1);
      expect(
        logger.uris,
        everyElement(
          predicate<Uri>(
            (uri) =>
                uri.queryParameters['sign'] == '[REDACTED]' &&
                !uri.toString().contains('opaque-fixture-value'),
          ),
        ),
      );
    },
  );
}

final class _ScriptedHttpAdapter implements HttpClientAdapter {
  _ScriptedHttpAdapter(this._statuses);

  final List<int> _statuses;
  int requests = 0;
  final List<bool> followRedirects = <bool>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    followRedirects.add(options.followRedirects);
    final status = _statuses[requests++];
    return ResponseBody.fromString(
      status == 405 ? 'Method Not Allowed' : '',
      status,
      headers: status == 302
          ? <String, List<String>>{
              'location': <String>['/plugin.php?id=zqlj_sign'],
            }
          : const <String, List<String>>{},
    );
  }
}

final class _VerifiedWaf implements ForumWafRecoveryDelegate {
  int calls = 0;

  @override
  Future<ForumWafRecoveryResult> recover(
    ForumWafRecoveryRequest request,
  ) async {
    calls += 1;
    return ForumWafRecoveryResult.verified;
  }
}

final class _RecordingLogger implements ForumClientLogger {
  final uris = <Uri>[];

  @override
  void requestStarted({
    required String operation,
    required String method,
    required Uri uri,
  }) => uris.add(uri);

  @override
  void requestFinished({
    required String operation,
    required String method,
    required Uri uri,
    required int? statusCode,
    required int elapsedMs,
  }) => uris.add(uri);

  @override
  void requestFailed({
    required String operation,
    required String method,
    required Uri uri,
    required String code,
    required int? statusCode,
  }) => uris.add(uri);
}
