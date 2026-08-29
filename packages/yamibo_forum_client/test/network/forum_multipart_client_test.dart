import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  test(
    'multipart WAF replay opens a fresh file stream exactly once per attempt',
    () async {
      final http = _MultipartHttpAdapter(<int>[405, 200]);
      final dio = Dio()..httpClientAdapter = http;
      final waf = _VerifiedWaf();
      final network = DioForumClientNetwork(
        config: ForumClientConfig(
          siteOrigin: Uri.parse('https://bbs.example.test/'),
          apiOrigin: Uri.parse('https://bbs.example.test/api/mobile/index.php'),
          userAgent: 'fixture-agent',
        ),
        cookies: MemoryForumCookieStore(),
        waf: waf,
        dio: dio,
      );
      var openReadCalls = 0;

      final result = await network.sendMultipart(
        ForumMultipartRequest(
          uri: Uri.parse(
            'https://bbs.example.test/api/mobile/index.php?module=forumupload',
          ),
          context: const ForumRequestContext(
            operation: 'fixture.multipart',
            module: 'forumupload',
          ),
          fields: const <String, String>{
            'uid': '30001',
            'hash': 'fixture-hash',
          },
          file: ForumMultipartFile(
            fieldName: 'Filedata',
            fileName: 'fixture.jpg',
            contentType: 'image/jpeg',
            contentLength: 3,
            openRead: () {
              openReadCalls += 1;
              return Stream.value(<int>[1, 2, 3]);
            },
          ),
        ),
      );

      expect(result, isA<ForumTransportSuccess<ForumMultipartResponse>>());
      expect(
        (result as ForumTransportSuccess<ForumMultipartResponse>).response.body,
        '42',
      );
      expect(http.requests, 2);
      expect(http.requestBodies, everyElement(isNotEmpty));
      expect(openReadCalls, 2);
      expect(waf.calls, 1);
    },
  );

  test('cancelled multipart request fails before opening a stream', () async {
    final cancellation = ForumRequestCancellation()..cancel();
    var opened = false;
    final network = DioForumClientNetwork(
      config: ForumClientConfig(
        siteOrigin: Uri.parse('https://bbs.example.test/'),
        userAgent: 'fixture-agent',
      ),
      cookies: MemoryForumCookieStore(),
      dio: Dio()..httpClientAdapter = _MultipartHttpAdapter(<int>[200]),
    );

    final result = await network.sendMultipart(
      ForumMultipartRequest(
        uri: Uri.parse('https://bbs.example.test/upload'),
        context: const ForumRequestContext(operation: 'fixture.cancel'),
        fields: const <String, String>{},
        file: ForumMultipartFile(
          fieldName: 'Filedata',
          fileName: 'fixture.jpg',
          contentType: 'image/jpeg',
          contentLength: 1,
          openRead: () {
            opened = true;
            return Stream.value(<int>[1]);
          },
        ),
        cancellation: cancellation,
      ),
    );

    expect(result, isA<ForumTransportError<ForumMultipartResponse>>());
    expect(opened, isFalse);
  });
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

final class _MultipartHttpAdapter implements HttpClientAdapter {
  _MultipartHttpAdapter(this._statuses);

  final List<int> _statuses;
  int requests = 0;
  final List<List<int>> requestBodies = <List<int>>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests += 1;
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    requestBodies.add(bytes);
    final status = _statuses.removeAt(0);
    return ResponseBody.fromString(status == 200 ? '42' : '', status);
  }
}
