import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  final siteOrigin = Uri.parse('https://bbs.example.invalid');
  final config = ForumClientConfig(
    siteOrigin: siteOrigin,
    apiOrigin: Uri.parse('https://api.example.invalid'),
    userAgent: 'mobile-fixture',
    resourceUserAgent: 'desktop-resource-fixture',
  );

  group('ForumResourceReferenceResolver', () {
    final resolver = ForumResourceReferenceResolver(siteOrigin: siteOrigin);

    test('normalizes same-site references and retains safe referer query', () {
      final reference = resolver.resolve(
        '/data/attachment/image.jpg#fragment',
        referer: Uri.parse(
          'https://bbs.example.invalid/forum.php?mod=viewthread&tid=1#post',
        ),
      );

      expect(
        reference?.uri.toString(),
        'https://bbs.example.invalid/data/attachment/image.jpg',
      );
      expect(
        reference?.referer.toString(),
        'https://bbs.example.invalid/forum.php?mod=viewthread&tid=1',
      );
      expect(reference?.origin, ForumResourceOrigin.sameSite);
    });

    test('strips query from third-party referers and rejects unsafe URIs', () {
      final reference = resolver.resolve(
        'https://cdn.example.invalid/image.png',
        referer: Uri.parse(
          'https://bbs.example.invalid/forum.php?mod=viewthread&tid=secret',
        ),
      );

      expect(
        reference?.referer.toString(),
        'https://bbs.example.invalid/forum.php',
      );
      expect(reference?.origin, ForumResourceOrigin.thirdParty);
      expect(resolver.resolve('file:///private/image.jpg'), isNull);
      expect(
        resolver.resolve('https://user:pass@example.invalid/a.jpg'),
        isNull,
      );
    });
  });

  group('DioForumClientNetwork resources', () {
    test('streams the image-signature prefix without losing bytes', () async {
      final bytes = <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        ...List<int>.generate(9000, (index) => index & 0xff),
      ];
      final adapter = _ScriptedResourceAdapter(<_ResourceResponse>[
        _ResourceResponse(
          bytes: bytes,
          headers: const <String, List<String>>{
            Headers.contentTypeHeader: <String>['image/png'],
            'etag': <String>['fixture-etag'],
          },
        ),
      ]);
      final network = _network(config, adapter: adapter);

      final result = await network.open(
        _request(siteOrigin, '/image.png', ifNoneMatch: 'old-etag'),
      );
      final success = result as ForumResourceSuccess;
      final received = await success.content.expand((chunk) => chunk).toList();

      expect(received, bytes);
      expect(success.eTag, 'fixture-etag');
      expect(success.fileExtension, '.png');
      expect(adapter.requests.single.headers['If-None-Match'], 'old-etag');
      expect(
        adapter.requests.single.headers['User-Agent'],
        'desktop-resource-fixture',
      );
    });

    test('same-site resource 405 recovers before exposing bytes', () async {
      final cookies = MemoryForumCookieStore();
      await cookies.merge(siteOrigin, const <String, String>{
        'auth': 'confirmed-auth',
      });
      final adapter = _ScriptedResourceAdapter(const <_ResourceResponse>[
        _ResourceResponse(
          statusCode: 405,
          headers: <String, List<String>>{
            'set-cookie': <String>['auth=deleted; Max-Age=0; Path=/'],
          },
        ),
        _ResourceResponse(
          bytes: <int>[0xff, 0xd8, 0xff, 0x00],
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['image/jpeg'],
          },
        ),
      ]);
      final waf = _RecordingWaf();
      final network = _network(
        config,
        adapter: adapter,
        cookies: cookies,
        waf: waf,
      );

      final result = await network.open(_request(siteOrigin, '/image.jpg'));
      final bytes = await (result as ForumResourceSuccess).content
          .expand((chunk) => chunk)
          .toList();

      expect(bytes, const <int>[0xff, 0xd8, 0xff, 0x00]);
      expect(adapter.requests, hasLength(2));
      expect(waf.calls, 1);
      expect(waf.lastRequest?.evidence, ForumWafEvidence.httpStatus405);
      expect(
        await cookies.read(siteOrigin),
        containsPair('auth', 'confirmed-auth'),
      );
    });

    test(
      'script-shaped HTTP 200 is invalid image content without WAF recovery',
      () async {
        final adapter = _ScriptedResourceAdapter(<_ResourceResponse>[
          _ResourceResponse(
            bytes:
                '<html><script>var arg1="fixture";</script></html>'.codeUnits,
            headers: const <String, List<String>>{
              Headers.contentTypeHeader: <String>['text/html'],
            },
          ),
        ]);
        final waf = _RecordingWaf();
        final network = _network(config, adapter: adapter, waf: waf);

        final result = await network.open(_request(siteOrigin, '/image.jpg'));

        expect(
          (result as ForumResourceError).failure.kind,
          ForumResourceFailureKind.invalidContent,
        );
        expect(adapter.requests, hasLength(1));
        expect(waf.calls, 0);
      },
    );

    test(
      'accepts signature-proven dynamic images with a misleading MIME type',
      () async {
        const bytes = <int>[0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];
        final adapter = _ScriptedResourceAdapter(const <_ResourceResponse>[
          _ResourceResponse(
            bytes: bytes,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
            },
          ),
        ]);
        final network = _network(config, adapter: adapter);

        final result = await network.open(
          _request(siteOrigin, '/forum.php?mod=image&aid=1&type=fixnone'),
        );
        final success = result as ForumResourceSuccess;

        expect(await success.content.expand((chunk) => chunk).toList(), bytes);
        expect(success.fileExtension, '.jpg');
      },
    );

    test('third-party resources never receive forum cookies', () async {
      final cookies = MemoryForumCookieStore();
      await cookies.merge(siteOrigin, const <String, String>{'sid': 'secret'});
      final adapter = _ScriptedResourceAdapter(const <_ResourceResponse>[
        _ResourceResponse(
          bytes: <int>[0xff, 0xd8, 0xff],
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['image/jpeg'],
          },
        ),
      ]);
      final network = _network(config, adapter: adapter, cookies: cookies);
      final resolver = ForumResourceReferenceResolver(siteOrigin: siteOrigin);
      final reference = resolver.resolve(
        'https://cdn.example.invalid/image.jpg',
        referer: Uri.parse(
          'https://bbs.example.invalid/forum.php?mod=viewthread&tid=1',
        ),
      )!;

      final result = await network.open(
        ForumResourceRequest(reference: reference),
      );

      expect(result, isA<ForumResourceSuccess>());
      expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
      expect(
        adapter.requests.single.headers['Referer'],
        'https://bbs.example.invalid/forum.php',
      );
    });

    test(
      'cross-host redirects strip cookies, query referer, and ETag',
      () async {
        final cookies = MemoryForumCookieStore();
        await cookies.merge(siteOrigin, const <String, String>{
          'sid': 'secret',
        });
        final adapter = _ScriptedResourceAdapter(const <_ResourceResponse>[
          _ResourceResponse(
            statusCode: 302,
            headers: <String, List<String>>{
              'location': <String>[
                'https://cdn.example.invalid/final-image.jpg',
              ],
            },
          ),
          _ResourceResponse(
            bytes: <int>[0xff, 0xd8, 0xff],
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>['image/jpeg'],
            },
          ),
        ]);
        final network = _network(config, adapter: adapter, cookies: cookies);

        final result = await network.open(
          _request(siteOrigin, '/redirect.jpg', ifNoneMatch: 'private-etag'),
        );

        expect(result, isA<ForumResourceSuccess>());
        expect(adapter.requests, hasLength(2));
        expect(adapter.requests.first.headers['Cookie'], 'sid=secret');
        expect(
          adapter.requests.first.headers['Referer'],
          'https://bbs.example.invalid/forum.php?mod=viewthread&tid=1',
        );
        expect(adapter.requests.first.headers['If-None-Match'], 'private-etag');
        expect(adapter.requests.last.headers.containsKey('Cookie'), isFalse);
        expect(
          adapter.requests.last.headers['Referer'],
          'https://bbs.example.invalid/forum.php',
        );
        expect(
          adapter.requests.last.headers.containsKey('If-None-Match'),
          isFalse,
        );
      },
    );

    test('rejects HTML presented as an image payload', () async {
      final adapter = _ScriptedResourceAdapter(<_ResourceResponse>[
        _ResourceResponse(
          bytes: '<html>not an image</html>'.codeUnits,
          headers: const <String, List<String>>{
            Headers.contentTypeHeader: <String>['text/html'],
          },
        ),
      ]);
      final network = _network(config, adapter: adapter);

      final result = await network.open(_request(siteOrigin, '/image.jpg'));

      expect(
        (result as ForumResourceError).failure.kind,
        ForumResourceFailureKind.invalidContent,
      );
    });

    test('rejects unrelated RIFF and ISO BMFF payloads', () async {
      final adapter = _ScriptedResourceAdapter(const <_ResourceResponse>[
        _ResourceResponse(
          bytes: <int>[
            0x52,
            0x49,
            0x46,
            0x46,
            0x04,
            0x00,
            0x00,
            0x00,
            0x57,
            0x41,
            0x56,
            0x45,
          ],
        ),
        _ResourceResponse(
          bytes: <int>[
            0x00,
            0x00,
            0x00,
            0x18,
            0x66,
            0x74,
            0x79,
            0x70,
            0x69,
            0x73,
            0x6f,
            0x6d,
          ],
        ),
      ]);
      final network = _network(config, adapter: adapter);

      final riff = await network.open(_request(siteOrigin, '/audio.bin'));
      final mp4 = await network.open(_request(siteOrigin, '/video.bin'));

      expect(
        (riff as ForumResourceError).failure.kind,
        ForumResourceFailureKind.invalidContent,
      );
      expect(
        (mp4 as ForumResourceError).failure.kind,
        ForumResourceFailureKind.invalidContent,
      );
    });
  });

  group('DioForumClientNetwork WAF detection', () {
    test('script-shaped HTTP 200 does not invoke recovery', () async {
      final adapter = _ScriptedResourceAdapter(<_ResourceResponse>[
        _ResourceResponse(
          bytes: '<html><script>var arg1="fixture";</script></html>'.codeUnits,
          headers: const <String, List<String>>{
            Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
          },
        ),
      ]);
      final waf = _RecordingWaf();
      final network = _network(config, adapter: adapter, waf: waf);

      final result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: siteOrigin.resolve('/index.php?mobile=2'),
          context: const ForumRequestContext(operation: 'fixture.read'),
        ),
      );

      expect(result, isA<ForumTransportSuccess<ForumResponse<Object?>>>());
      expect(waf.calls, 0);
      expect(adapter.requests, hasLength(1));
    });

    test('HTTP 405 fails closed when no WAF delegate is installed', () async {
      final adapter = _ScriptedResourceAdapter(const <_ResourceResponse>[
        _ResourceResponse(statusCode: 405),
      ]);
      final network = _network(config, adapter: adapter);

      final result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: siteOrigin.resolve('/index.php?mobile=2'),
          context: const ForumRequestContext(operation: 'fixture.read'),
        ),
      );

      final failure =
          (result as ForumTransportError<ForumResponse<Object?>>).failure;
      expect(failure.code, 'waf_unavailable');
      expect(failure.statusCode, 405);
      expect(adapter.requests, hasLength(1));
    });

    test('HTTP 405 invokes recovery and replays exactly once', () async {
      final cookies = MemoryForumCookieStore();
      await cookies.merge(siteOrigin, const <String, String>{
        'auth': 'confirmed-auth',
      });
      final adapter = _ScriptedResourceAdapter(<_ResourceResponse>[
        const _ResourceResponse(
          statusCode: 405,
          headers: <String, List<String>>{
            'set-cookie': <String>['auth=deleted; Max-Age=0; Path=/'],
          },
        ),
        _ResourceResponse(
          bytes: 'ok'.codeUnits,
          headers: const <String, List<String>>{
            Headers.contentTypeHeader: <String>['text/plain; charset=utf-8'],
          },
        ),
      ]);
      final waf = _RecordingWaf();
      final network = _network(
        config,
        adapter: adapter,
        cookies: cookies,
        waf: waf,
      );

      final result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.post,
          uri: siteOrigin.resolve('/forum.php?mod=fixture'),
          context: const ForumRequestContext(operation: 'fixture.write'),
          body: const <String, String>{'value': '1'},
        ),
      );

      expect(result, isA<ForumTransportSuccess<ForumResponse<Object?>>>());
      expect(waf.calls, 1);
      expect(waf.lastRequest?.evidence, ForumWafEvidence.httpStatus405);
      expect(adapter.requests, hasLength(2));
      expect(
        await cookies.read(siteOrigin),
        containsPair('auth', 'confirmed-auth'),
      );
    });
  });
}

DioForumClientNetwork _network(
  ForumClientConfig config, {
  required HttpClientAdapter adapter,
  ForumCookieStore? cookies,
  ForumWafRecoveryDelegate? waf,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return DioForumClientNetwork(
    config: config,
    cookies: cookies ?? MemoryForumCookieStore(),
    waf: waf,
    dio: dio,
  );
}

ForumResourceRequest _request(
  Uri siteOrigin,
  String path, {
  String? ifNoneMatch,
}) {
  final resolver = ForumResourceReferenceResolver(siteOrigin: siteOrigin);
  return ForumResourceRequest(
    reference: resolver.resolve(
      path,
      referer: siteOrigin.resolve('/forum.php?mod=viewthread&tid=1'),
    )!,
    ifNoneMatch: ifNoneMatch,
  );
}

final class _RecordingWaf implements ForumWafRecoveryDelegate {
  int calls = 0;
  ForumWafRecoveryRequest? lastRequest;

  @override
  Future<ForumWafRecoveryResult> recover(
    ForumWafRecoveryRequest request,
  ) async {
    calls += 1;
    lastRequest = request;
    return ForumWafRecoveryResult.verified;
  }
}

final class _ResourceResponse {
  const _ResourceResponse({
    this.statusCode = 200,
    this.bytes = const <int>[],
    this.headers = const <String, List<String>>{},
  });

  final int statusCode;
  final List<int> bytes;
  final Map<String, List<String>> headers;
}

final class _ScriptedResourceAdapter implements HttpClientAdapter {
  _ScriptedResourceAdapter(List<_ResourceResponse> responses)
    : _responses = List<_ResourceResponse>.of(responses);

  final List<_ResourceResponse> _responses;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_responses.isEmpty) throw StateError('No scripted response');
    final response = _responses.removeAt(0);
    return ResponseBody.fromBytes(
      response.bytes,
      response.statusCode,
      headers: response.headers,
    );
  }
}
