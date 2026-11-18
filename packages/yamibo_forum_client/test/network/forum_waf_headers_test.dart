import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

const _rateLimit = {
  'x-tengine-error': ['denied by http_auto_ratelimit'],
};
const _otherDenial = {
  'x-tengine-error': ['denied by Referer ACL'],
};
final _site = Uri.parse('https://bbs.example.test');

void main() {
  for (final type in ForumResponseType.values) {
    test(
      '$type recovers header challenge before parsing and reuses cookies',
      () async {
        final cookies = MemoryForumCookieStore();
        final http = _Http([
          const _Reply(
            headers: {
              ..._rateLimit,
              'content-length': ['4321'],
            },
            body: '<script>opaque challenge</script>',
          ),
          const _Reply(body: '{"ok":true}'),
        ]);
        final waf = _Waf(
          onRecover: () => cookies.merge(_site, {'pass': 'fresh'}),
        );
        final network = _network(http, waf, cookies: cookies);
        final result = await network.send(_request(type: type));
        final response =
            (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
        expect(response.statusCode, 200);
        expect(
          waf.requests.single.evidence,
          ForumWafEvidence.httpAutoRatelimit,
        );
        expect(http.requests, hasLength(2));
        expect(http.requests.last.headers['Cookie'], contains('pass=fresh'));
        if (type == ForumResponseType.json) expect(response.body, {'ok': true});
      },
    );

    test(
      '$type persistent header challenge replays only once and keeps 200',
      () async {
        final http = _Http([
          const _Reply(headers: _rateLimit),
          const _Reply(headers: _rateLimit),
        ]);
        final waf = _Waf();
        final result = await _network(http, waf).send(_request(type: type));
        final failure =
            (result as ForumTransportError<ForumResponse<Object?>>).failure;
        expect(failure.code, 'security_challenge_persisted');
        expect(failure.statusCode, 200);
        expect(failure.isSecurityFailure, isTrue);
        expect(waf.requests, hasLength(1));
        expect(http.requests, hasLength(2));
      },
    );
  }

  test(
    'unrecognized denial fails without recovery or merging response cookies',
    () async {
      final http = _Http([
        const _Reply(
          headers: {
            ..._otherDenial,
            'set-cookie': ['auth=untrusted; Path=/'],
          },
        ),
      ]);
      final waf = _Waf();
      final cookies = MemoryForumCookieStore();
      final result = await _network(
        http,
        waf,
        cookies: cookies,
      ).send(_request());
      final failure =
          (result as ForumTransportError<ForumResponse<Object?>>).failure;
      expect(failure.code, 'security_access_denied');
      expect(failure.isSecurityFailure, isTrue);
      expect(waf.requests, isEmpty);
      expect(await cookies.read(_site), isEmpty);
    },
  );

  test(
    'disabled replay never launches a browser for the new challenge',
    () async {
      final http = _Http([const _Reply(headers: _rateLimit)]);
      final waf = _Waf();
      final result = await _network(
        http,
        waf,
      ).send(_request(allowReplay: false));
      expect(
        (result as ForumTransportError<ForumResponse<Object?>>).failure.code,
        'security_verification_not_completed',
      );
      expect(waf.requests, isEmpty);
      expect(http.requests, hasLength(1));
    },
  );

  test('cancellation during recovery prevents replay', () async {
    final cancellation = ForumRequestCancellation();
    final http = _Http([const _Reply(headers: _rateLimit)]);
    final waf = _Waf(onRecover: () async => cancellation.cancel());
    final result = await _network(
      http,
      waf,
    ).send(_request(cancellation: cancellation));
    expect(
      (result as ForumTransportError<ForumResponse<Object?>>).failure.kind,
      ForumTransportFailureKind.cancelled,
    );
    expect(http.requests, hasLength(1));
  });

  test('adapter leaves ordinary streams lazy and delegates close', () async {
    var listened = false;
    final source = StreamController<Uint8List>(onListen: () => listened = true);
    final stream = source.stream;
    final http = _Http([_Reply(stream: stream)]);
    final adapter = ForumWafHttpClientAdapter(
      delegate: http,
      isManagedUri: (uri) => uri.host == _site.host,
    );
    final response = await adapter.fetch(
      RequestOptions(path: _site.toString()),
      null,
      null,
    );
    expect(response.stream, same(stream));
    expect(listened, isFalse);
    adapter.close(force: true);
    expect(http.closed, isTrue);
    await response.stream.listen(null).cancel();
    await source.close();
  });

  test('third-party response headers never trigger forum recovery', () async {
    final http = _Http([
      const _Reply(
        headers: {
          ..._rateLimit,
          'content-type': ['text/html'],
        },
        body: 'third-party',
      ),
    ]);
    final waf = _Waf();
    final result = await _network(
      http,
      waf,
    ).send(_request(uri: Uri.parse('https://other.test/a')));
    expect(result, isA<ForumTransportSuccess<ForumResponse<Object?>>>());
    expect(waf.requests, isEmpty);
  });

  for (final status in [200, 304]) {
    test(
      'image $status header challenge is retired before exposing bytes',
      () async {
        var cancelled = false;
        final controller = StreamController<Uint8List>(
          onCancel: () => cancelled = true,
        );
        final http = _Http([
          _Reply(
            status: status,
            headers: _rateLimit,
            stream: controller.stream,
          ),
          const _Reply(
            body: 'image',
            headers: {
              'content-type': ['image/jpeg'],
            },
          ),
        ]);
        final waf = _Waf();
        final result = await _network(http, waf).open(_image());
        expect(
          await (result as ForumResourceSuccess).content
              .expand((b) => b)
              .toList(),
          utf8.encode('image'),
        );
        expect(cancelled, isTrue);
        expect(
          waf.requests.single.evidence,
          ForumWafEvidence.httpAutoRatelimit,
        );
        await controller.close();
      },
    );
  }

  test(
    'image unknown denial cannot be cached even with an image MIME',
    () async {
      final http = _Http([
        const _Reply(
          headers: {
            ..._otherDenial,
            'content-type': ['image/jpeg'],
          },
        ),
      ]);
      final waf = _Waf();
      final result = await _network(http, waf).open(_image());
      expect(
        (result as ForumResourceError).failure.code,
        'security_access_denied',
      );
      expect(waf.requests, isEmpty);
    },
  );

  test(
    'multipart uses header evidence and reports a persistent 200 accurately',
    () async {
      final http = _Http([
        const _Reply(headers: _rateLimit),
        const _Reply(headers: _rateLimit),
      ]);
      final waf = _Waf();
      final result = await _network(http, waf).sendMultipart(
        ForumMultipartRequest(
          uri: _site.resolve('/upload'),
          context: const ForumRequestContext(operation: 'fixture.upload'),
          fields: const {},
          file: ForumMultipartFile(
            fieldName: 'file',
            fileName: 'fixture.jpg',
            contentType: 'image/jpeg',
            contentLength: 1,
            openRead: () => Stream.value([1]),
          ),
        ),
      );
      final failure =
          (result as ForumTransportError<ForumMultipartResponse>).failure;
      expect(failure.code, 'security_challenge_persisted');
      expect(failure.statusCode, 200);
      expect(waf.requests.single.evidence, ForumWafEvidence.httpAutoRatelimit);
      expect(http.requests, hasLength(2));
    },
  );
}

ForumRequest _request({
  ForumResponseType type = ForumResponseType.text,
  bool allowReplay = true,
  ForumRequestCancellation? cancellation,
  Uri? uri,
}) => ForumRequest(
  method: ForumRequestMethod.get,
  uri: uri ?? _site.resolve('/index.php'),
  context: const ForumRequestContext(operation: 'fixture.read'),
  responseType: type,
  allowWafReplay: allowReplay,
  cancellation: cancellation,
);

ForumResourceRequest _image() => ForumResourceRequest(
  reference: ForumResourceReferenceResolver(
    siteOrigin: _site,
  ).resolve('/image.jpg', referer: _site)!,
);

DioForumClientNetwork _network(
  _Http http,
  _Waf waf, {
  ForumCookieStore? cookies,
}) => DioForumClientNetwork(
  config: ForumClientConfig(siteOrigin: _site),
  cookies: cookies ?? MemoryForumCookieStore(),
  waf: waf,
  dio: Dio()..httpClientAdapter = http,
);

class _Waf implements ForumWafRecoveryDelegate {
  _Waf({this.onRecover});
  final Future<void> Function()? onRecover;
  final requests = <ForumWafRecoveryRequest>[];
  @override
  Future<ForumWafRecoveryResult> recover(
    ForumWafRecoveryRequest request,
  ) async {
    requests.add(request);
    await onRecover?.call();
    return ForumWafRecoveryResult.verified;
  }
}

class _Reply {
  const _Reply({
    this.status = 200,
    this.headers = const {},
    this.body = '',
    this.stream,
  });
  final int status;
  final Map<String, List<String>> headers;
  final String body;
  final Stream<Uint8List>? stream;
}

class _Http implements HttpClientAdapter {
  _Http(this.replies);
  final List<_Reply> replies;
  final requests = <RequestOptions>[];
  bool closed = false;
  @override
  void close({bool force = false}) => closed = true;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    await requestStream?.drain<void>();
    final reply = replies.removeAt(0);
    final headers = {
      'content-type': ['application/json'],
      ...reply.headers,
    };
    return ResponseBody(
      reply.stream ?? Stream.value(Uint8List.fromList(utf8.encode(reply.body))),
      reply.status,
      headers: headers,
    );
  }
}
