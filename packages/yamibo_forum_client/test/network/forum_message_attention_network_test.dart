import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/parsing/discuz_html_document.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

import '../fixtures/message_attention_html_fixtures.dart';

void main() {
  test('no observer preserves the original transport and ports', () {
    final network = _FullNetwork(_success(_apiBody()));
    final client = _client(network);
    final factory = ForumClientAdapterFactory(
      config: _config,
      network: network,
    );

    expect(client.network, same(network));
    expect(factory.network, same(network));
    expect(client.resources, same(network));
    expect(client.multipart, same(network));
  });

  test(
    'captures before send and delivers the exact captured context',
    () async {
      final owner = Object();
      final context = ForumMessageAttentionRequestContext(
        viewerUserId: '42',
        requestSequence: 17,
        ownerToken: owner,
      );
      final observer = _Observer(context: context);
      final original = _success(_apiBody());
      final network = _Network(original)
        ..beforeReturn = () {
          expect(observer.captures, 1);
          observer.context = null;
        };
      final request = _apiRequest();
      final result = await _client(network, observer).network.send(request);

      expect(result, same(original));
      expect(network.requests.single, same(request));
      expect(observer.deliveries.single.context, same(context));
      expect(observer.deliveries.single.context.ownerToken, same(owner));
      expect(observer.deliveries.single.observation.viewerUserId, '42');
      expect(
        observer.deliveries.single.observation.combined,
        ForumMessageAttentionState.present,
      );
    },
  );

  test(
    'observes HTML and decoded/string JSON without replacing bodies',
    () async {
      final samples = <(ForumRequest, Object?)>[
        (_htmlRequest(), mobileAttentionHtml(messageDot: true)),
        (_apiRequest(), _apiBody()),
        (_apiRequest(), jsonEncode(_apiBody())),
        (_apiRequest(), '\uFEFF ${jsonEncode(_apiBody())}'),
        (_apiRequest(), 'ï»¿ ${jsonEncode(_apiBody())}'),
      ];
      for (final (request, body) in samples) {
        final observer = _Observer();
        final original = _success(body, uri: request.uri);
        final result = await _client(
          _Network(original),
          observer,
        ).network.send(request);
        expect(result, same(original));
        expect(
          (result as ForumTransportSuccess<ForumResponse<Object?>>)
              .response
              .body,
          same(body),
        );
        expect(observer.deliveries, hasLength(1));
      }
    },
  );

  test(
    'HTML observation reuses the response DOM already used by business',
    () async {
      final source = mobileAttentionHtml(messageDot: true);
      final original = _success(source, uri: _htmlUri);
      final decoded = DiscuzHtmlDocument.forResponse(original.response);
      final document = decoded.document;
      // A test-only DOM change distinguishes reuse from reparsing the original
      // source. Production consumers must treat the shared DOM as read-only.
      document.querySelector('.foot em.mb .ico_msg')!.remove();
      final observer = _Observer();

      final result = await _client(
        _Network(original),
        observer,
      ).network.send(_htmlRequest());

      expect(result, same(original));
      expect(original.response.body, same(source));
      expect(DiscuzHtmlDocument.forResponse(original.response), same(decoded));
      expect(decoded.document, same(document));
      expect(
        observer.deliveries.single.observation.combined,
        ForumMessageAttentionState.absent,
      );
    },
  );

  test(
    'a reused HTML response never reuses request ownership or sequence',
    () async {
      final original = _success(
        mobileAttentionHtml(messageDot: true),
        uri: _htmlUri,
      );
      final observer = _Observer();
      final client = _client(_Network(original), observer);
      final firstOwner = Object();
      final nextOwner = Object();
      final firstContext = ForumMessageAttentionRequestContext(
        viewerUserId: '42',
        requestSequence: 10,
        ownerToken: firstOwner,
      );
      final otherContext = ForumMessageAttentionRequestContext(
        viewerUserId: '84',
        requestSequence: 11,
        ownerToken: Object(),
      );
      final nextContext = ForumMessageAttentionRequestContext(
        viewerUserId: '42',
        requestSequence: 12,
        ownerToken: nextOwner,
      );

      observer.context = firstContext;
      expect(await client.network.send(_htmlRequest()), same(original));
      final document = DiscuzHtmlDocument.forResponse(
        original.response,
      ).document;
      observer.context = otherContext;
      expect(await client.network.send(_htmlRequest()), same(original));
      observer.context = nextContext;
      expect(await client.network.send(_htmlRequest()), same(original));

      expect(observer.captures, 3);
      expect(observer.deliveries.map((delivery) => delivery.context), [
        same(firstContext),
        same(nextContext),
      ]);
      expect(
        DiscuzHtmlDocument.forResponse(original.response).document,
        same(document),
      );
    },
  );

  test(
    'without an observer business retains its response and decoded DOM',
    () async {
      final source = mobileAttentionHtml(messageDot: true);
      final original = _success(source, uri: _htmlUri);
      final network = _Network(original);
      final client = _client(network);
      expect(client.network, same(network));
      expect(await client.network.send(_htmlRequest()), same(original));

      final decoded = DiscuzHtmlDocument.forResponse(original.response);
      final document = decoded.document;
      expect(
        DiscuzHtmlDocument.forResponse(original.response).document,
        same(document),
      );
      expect(decoded.hasUnexpectedEof, isFalse);
      expect(original.response.body, same(source));
    },
  );

  test(
    'POST, bytes, GET bodies and unsafe requested endpoints are not sampled',
    () async {
      final requests = <ForumRequest>[
        _apiRequest(method: ForumRequestMethod.post),
        _apiRequest(responseType: ForumResponseType.bytes),
        _apiRequest(body: const {'probe': 'unsafe'}),
        _apiRequest(
          uri: _site.resolve('/api/mobile/index.php?module=mypm&version=1'),
        ),
        _apiRequest(
          uri: _site.resolve(
            '/api/mobile/index.php?module=mynotelist&version=3',
          ),
        ),
        _apiRequest(
          uri: _site.resolve('/api/mobile/index.php?module=login&version=1'),
        ),
        _apiRequest(
          uri: _site.resolve(
            '/api/mobile/index.php?module=checknewpm&version=4',
          ),
        ),
        _htmlRequest(uri: _site.resolve('/home.php?mod=space&do=pm')),
        _htmlRequest(uri: _site.resolve('/home.php?mod=space&do=notice')),
        _htmlRequest(uri: _site.resolve('/forum.php?mod=post')),
        _htmlRequest(uri: _site.resolve('/forum.php?mod=viewthread&inajax=1')),
        _apiRequest(
          uri: Uri.parse(
            'https://other.example.test/api/mobile/index.php?module=profile',
          ),
        ),
      ];
      for (final request in requests) {
        final observer = _Observer();
        // Even a consuming GET redirected to an otherwise safe final URI must
        // not be repurposed as post-consumption evidence.
        final original = _success(
          request.responseType == ForumResponseType.text
              ? mobileAttentionHtml(messageDot: true)
              : _apiBody(),
          uri: request.responseType == ForumResponseType.text
              ? _htmlUri
              : _apiUri,
        );
        final result = await _client(
          _Network(original),
          observer,
        ).network.send(request);
        expect(result, same(original));
        expect(observer.captures, 0, reason: request.uri.toString());
        expect(observer.deliveries, isEmpty);
      }
    },
  );

  test(
    'failure, redirect, 304, challenge and absent statuses remain unchanged',
    () async {
      final originals = <ForumTransportResult<ForumResponse<Object?>>>[
        const ForumTransportError(
          ForumTransportFailure(
            kind: ForumTransportFailureKind.network,
            code: 'fixture',
          ),
        ),
        for (final status in <int?>[null, 199, 302, 304, 401, 405, 500])
          _success(_apiBody(), status: status),
      ];
      for (final original in originals) {
        final observer = _Observer();
        expect(
          await _client(
            _Network(original),
            observer,
          ).network.send(_apiRequest()),
          same(original),
        );
        expect(observer.deliveries, isEmpty);
      }
    },
  );

  test(
    'an unknown requested API version cannot be rescued by a redirect',
    () async {
      final observer = _Observer();
      final original = _success(_apiBody(), uri: _apiUri);
      final request = _apiRequest(
        uri: _site.resolve('/api/mobile/index.php?module=profile&version=99'),
      );
      expect(
        await _client(_Network(original), observer).network.send(request),
        same(original),
      );
      expect(observer.captures, 0);
      expect(observer.deliveries, isEmpty);
    },
  );

  test('explicit authentication and formhash contexts are excluded', () async {
    for (final pageKind in <String>['authentication', 'formhash']) {
      final observer = _Observer();
      final original = _success(_apiBody());
      final request = _apiRequest(
        context: ForumRequestContext(
          operation: 'profile',
          module: 'profile',
          pageKind: pageKind,
        ),
      );
      expect(
        await _client(_Network(original), observer).network.send(request),
        same(original),
      );
      expect(observer.captures, 0);
      expect(observer.deliveries, isEmpty);
    }
    // A descriptive operation containing "auth" has no exclusion authority;
    // ordinary profile reads retain their supported passive evidence.
    final observer = _Observer();
    await _client(_Network(_success(_apiBody())), observer).network.send(
      _apiRequest(
        context: const ForumRequestContext(
          operation: 'author.profile.read',
          module: 'profile',
          pageKind: 'profile',
        ),
      ),
    );
    expect(observer.deliveries, hasLength(1));
  });

  test(
    'standard session resolution marks auth without suppressing profiles',
    () async {
      final observer = _Observer();
      final network = _Network(
        _success(
          _apiBody(version: '4'),
          uri: _site.resolve('/api/mobile/index.php?module=profile&version=4'),
        ),
      );
      final client = _client(network, observer);
      expect(await client.resolveSession(), isA<ForumSessionAuthenticated>());
      expect(network.requests.single.context.pageKind, 'authentication');
      expect(network.requests.single.uri.queryParameters['version'], '4');
      expect(observer.captures, 0);
      expect(observer.deliveries, isEmpty);
      final ordinary = await client.currentUserProfile!.load(
        const CurrentUserProfileQuery(),
      );
      expect(ordinary.isSuccess, isTrue);
      expect(network.requests.last.context.pageKind, isNull);
      expect(observer.captures, 1);
      expect(observer.deliveries, hasLength(1));
    },
  );

  test(
    'both standard formhash source choices mark non-observable preflights',
    () async {
      for (final preferProfile in <bool>[true, false]) {
        final observer = _Observer();
        final body = _apiBody(version: '4');
        (body['Variables'] as Map<String, Object?>)['formhash'] =
            'fixture-hash';
        final network = _Network(
          _success(
            body,
            uri: _site.resolve(
              '/api/mobile/index.php?module=${preferProfile ? 'profile' : 'forumindex'}&version=4',
            ),
          ),
        );
        final result = await _client(
          network,
          observer,
        ).formhashProvider.loadFormhash(preferProfile: preferProfile);
        expect(result, isA<ForumFormhashSuccess>());
        expect(network.requests.single.context.pageKind, 'formhash');
        expect(
          network.requests.single.uri.queryParameters['module'],
          preferProfile ? 'profile' : 'forumindex',
        );
        expect(network.requests.single.uri.queryParameters['version'], '4');
        expect(observer.captures, 0);
        expect(observer.deliveries, isEmpty);
      }
    },
  );

  test(
    'valid request cannot sample a foreign or consuming final response',
    () async {
      for (final finalUri in <Uri>[
        Uri.parse(
          'https://other.example.test/api/mobile/index.php?module=profile',
        ),
        _site.resolve('/api/mobile/index.php?module=mypm&version=1'),
        _site.resolve('/member.php?mod=logging'),
      ]) {
        final observer = _Observer();
        final original = _success(_apiBody(), uri: finalUri);
        expect(
          await _client(
            _Network(original),
            observer,
          ).network.send(_apiRequest()),
          same(original),
        );
        expect(observer.deliveries, isEmpty);
      }
    },
  );

  test(
    'malformed, error, wrong-viewer and navigation-free bodies do not clear',
    () async {
      final samples = <(ForumRequest, Object?)>[
        (_apiRequest(), '{malformed'),
        (
          _apiRequest(),
          <String, Object?>{
            ..._apiBody(),
            'Message': const {'messageval': 'login_required'},
          },
        ),
        (_apiRequest(), _apiBody(viewer: '43')),
        (_apiRequest(), <int>[1, 2, 3]),
        (_htmlRequest(), mobileAttentionHtml(includeFooter: false)),
        (_htmlRequest(), mobileAttentionHtml(viewerUserId: '43')),
        (_htmlRequest(), '<html><head></head><body>incomplete'),
      ];
      for (final (request, body) in samples) {
        final observer = _Observer();
        final original = _success(body, uri: request.uri);
        expect(
          await _client(_Network(original), observer).network.send(request),
          same(original),
        );
        expect(observer.deliveries, isEmpty);
      }
    },
  );

  test(
    'capture and delivery failures cannot affect a successful read',
    () async {
      for (final observer in <_Observer>[
        _Observer()..throwDuringCapture = true,
        _Observer()..throwDuringDelivery = true,
        _Observer(context: null),
      ]) {
        final original = _success(_apiBody());
        final network = _Network(original);
        expect(
          await _client(network, observer).network.send(_apiRequest()),
          same(original),
        );
        expect(network.requests, hasLength(1));
      }
    },
  );

  test(
    'cancellation before or during transport prevents observation',
    () async {
      final cancelled = ForumRequestCancellation()..cancel();
      final before = _Observer();
      final original = _success(_apiBody());
      expect(
        await _client(
          _Network(original),
          before,
        ).network.send(_apiRequest(cancellation: cancelled)),
        same(original),
      );
      expect(before.captures, 0);
      expect(before.deliveries, isEmpty);

      final inFlight = ForumRequestCancellation();
      final observer = _Observer();
      final network = _DeferredNetwork(original);
      final result = _client(
        network,
        observer,
      ).network.send(_apiRequest(cancellation: inFlight));
      expect(observer.captures, 1);
      inFlight.cancel();
      network.complete();
      expect(await result, same(original));
      expect(observer.deliveries, isEmpty);
    },
  );

  test(
    'all capability combinations retain ports without adding unsupported ones',
    () {
      final combinations = <(_Network, bool, bool)>[
        (_Network(_success(_apiBody())), false, false),
        (_ResourceNetwork(_success(_apiBody())), true, false),
        (_MultipartNetwork(_success(_apiBody())), false, true),
        (_FullNetwork(_success(_apiBody())), true, true),
      ];
      for (final (network, resources, multipart) in combinations) {
        final observed = _client(network, _Observer()).network;
        expect(observed is ForumResourceClient, resources);
        expect(observed is ForumMultipartClient, multipart);
      }
    },
  );

  test(
    'resource stream and multipart delegate unchanged and are never sampled',
    () async {
      final observer = _Observer();
      final network = _FullNetwork(_success(_apiBody()));
      final client = _client(network, observer);
      final reference = ForumResourceReferenceResolver(
        siteOrigin: _site,
      ).resolve('/image.png', referer: _htmlUri)!;
      final resourceRequest = ForumResourceRequest(reference: reference);
      expect(
        await client.resources.open(resourceRequest),
        same(network.resourceResult),
      );
      expect(network.resourceRequest, same(resourceRequest));
      expect(network.streamListened, isFalse);

      final multipartRequest = ForumMultipartRequest(
        uri: _apiUri,
        context: const ForumRequestContext(operation: 'upload.fixture'),
        fields: const {'field': 'value'},
        file: ForumMultipartFile(
          fieldName: 'file',
          fileName: 'fixture.png',
          contentType: 'image/png',
          contentLength: 1,
          openRead: () => Stream.value(<int>[1]),
        ),
      );
      expect(
        await client.multipart!.sendMultipart(multipartRequest),
        same(network.multipartResult),
      );
      expect(network.multipartRequest, same(multipartRequest));
      expect(observer.captures, 0);
      expect(observer.deliveries, isEmpty);
    },
  );

  test('only the final successful WAF replay is observed once', () async {
    final observer = _Observer();
    final http = _WafHttpAdapter();
    final waf = _VerifiedWaf();
    final transport = DioForumClientNetwork(
      config: _config,
      cookies: MemoryForumCookieStore(),
      waf: waf,
      dio: Dio()..httpClientAdapter = http,
    );
    final result = await _client(
      transport,
      observer,
    ).network.send(_apiRequest());
    expect(result, isA<ForumTransportSuccess<ForumResponse<Object?>>>());
    expect(http.requests, 2);
    expect(waf.calls, 1);
    expect(observer.captures, 1);
    expect(observer.deliveries, hasLength(1));
  });

  test(
    'standard adapters observe once while document/snapshot replay stays silent',
    () async {
      final body = mobileAttentionHtml(
        messageDot: true,
        content: '''
      <div class="forumlist">
        <a class="subforumshow" href="#regular"><h2>Regular</h2></a>
        <div id="regular"><a class="murl" href="forum.php?mod=forumdisplay&amp;fid=30">
          <span class="mtit">Fixture</span><span class="mtxt">Forum</span>
        </a></div>
      </div>
    ''',
      );
      final network = _Network(
        _success(body, uri: _site.resolve('/index.php?mobile=2')),
      );
      final observer = _Observer();
      final documents = MemoryForumDocumentStore();
      final snapshots = MemoryForumSnapshotStore();
      final client = YamiboForumClientBuilder(
        config: _config,
        network: network,
        documentStore: documents,
        snapshotStore: snapshots,
        messageAttentionObserver: observer,
      ).buildStandardClient();
      final repository = client.forumHome!;
      final fresh = await repository.loadHome(
        const ForumHomeQuery(),
        cachePolicy: CacheLoadPolicy.networkFirst,
      );
      expect(fresh.isSuccess, isTrue);
      expect(observer.deliveries, hasLength(1));
      final cached = await repository.loadHome(const ForumHomeQuery());
      expect(cached.isSuccess, isTrue);
      expect(
        (cached
                as DataReadSuccess<
                  ForumHomeDocument,
                  ForumHomeReadCapabilities
                >)
            .metadata
            .origin,
        DataReadOrigin.freshSnapshot,
      );
      expect(await repository.readCached(const ForumHomeQuery()), isNotNull);

      final documentOnly = ForumClientAdapterFactory(
        config: _config,
        network: network,
        documentStore: documents,
        messageAttentionObserver: observer,
      ).createHtmlForumHome().home;
      final replay = await documentOnly.readCached(const ForumHomeQuery());
      expect(replay?.metadata.origin, DataReadOrigin.cachedDocumentFallback);
      expect(network.requests, hasLength(1));
      expect(observer.captures, 1);
      expect(observer.deliveries, hasLength(1));
    },
  );
}

final _site = Uri.parse('https://bbs.example.test');
final _htmlUri = _site.resolve('/forum.php');
final _apiUri = _site.resolve('/api/mobile/index.php?module=profile&version=1');
final _config = ForumClientConfig(siteOrigin: _site, apiOrigin: _apiUri);

Map<String, Object?> _apiBody({String viewer = '42', String version = '1'}) => {
  'Version': version,
  'Variables': <String, Object?>{
    'member_uid': viewer,
    'member_username': 'Fixture viewer',
    'space': <String, Object?>{},
    'notice': <String, Object?>{
      'newpm': '1',
      'newprompt': '0',
      'newmypost': '0',
    },
  },
};

ForumRequest _apiRequest({
  Uri? uri,
  ForumRequestMethod method = ForumRequestMethod.get,
  ForumResponseType responseType = ForumResponseType.json,
  Object? body,
  ForumRequestCancellation? cancellation,
  ForumRequestContext? context,
}) => ForumRequest(
  method: method,
  uri: uri ?? _apiUri,
  context: context ?? const ForumRequestContext(operation: 'fixture.read'),
  responseType: responseType,
  body: body,
  cancellation: cancellation,
);

ForumRequest _htmlRequest({Uri? uri}) => ForumRequest(
  method: ForumRequestMethod.get,
  uri: uri ?? _htmlUri,
  context: const ForumRequestContext(operation: 'fixture.html'),
);

ForumTransportSuccess<ForumResponse<Object?>> _success(
  Object? body, {
  Uri? uri,
  int? status = 200,
}) => ForumTransportSuccess(
  ForumResponse<Object?>(
    uri: uri ?? _apiUri,
    statusCode: status,
    headers: const <String, List<String>>{},
    body: body,
  ),
);

YamiboForumClient _client(
  ForumClientNetwork network, [
  ForumMessageAttentionObserver? observer,
]) => YamiboForumClientBuilder(
  config: _config,
  network: network,
  messageAttentionObserver: observer,
).buildStandardClient();

final class _Observer implements ForumMessageAttentionObserver {
  _Observer({
    this.context = const ForumMessageAttentionRequestContext(
      viewerUserId: '42',
      requestSequence: 1,
      ownerToken: 'fixture-owner',
    ),
  });
  ForumMessageAttentionRequestContext? context;
  int captures = 0;
  bool throwDuringCapture = false;
  bool throwDuringDelivery = false;
  final deliveries =
      <
        ({
          ForumMessageAttentionObservation observation,
          ForumMessageAttentionRequestContext context,
        })
      >[];

  @override
  ForumMessageAttentionRequestContext? captureRequest() {
    captures++;
    if (throwDuringCapture) throw StateError('fixture');
    return context;
  }

  @override
  void onObservation(
    ForumMessageAttentionObservation observation, {
    required ForumMessageAttentionRequestContext context,
  }) {
    deliveries.add((observation: observation, context: context));
    if (throwDuringDelivery) throw StateError('fixture');
  }
}

class _Network implements ForumClientNetwork {
  _Network(this.result);
  final ForumTransportResult<ForumResponse<Object?>> result;
  final requests = <ForumRequest>[];
  void Function()? beforeReturn;

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    beforeReturn?.call();
    return result;
  }
}

final class _DeferredNetwork extends _Network {
  _DeferredNetwork(super.result);
  final _done = Completer<void>();
  void complete() => _done.complete();

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    await _done.future;
    return result;
  }
}

class _ResourceNetwork extends _Network implements ForumResourceClient {
  _ResourceNetwork(super.result);
  ForumResourceRequest? resourceRequest;
  bool streamListened = false;
  late final resourceResult = ForumResourceSuccess(
    uri: _site.resolve('/image.png'),
    statusCode: 200,
    content: Stream<List<int>>.multi((controller) {
      streamListened = true;
      controller.add(<int>[1]);
      controller.close();
    }),
    validUntil: DateTime.utc(2030),
  );

  @override
  Future<ForumResourceResult> open(ForumResourceRequest request) async {
    resourceRequest = request;
    return resourceResult;
  }
}

class _MultipartNetwork extends _Network implements ForumMultipartClient {
  _MultipartNetwork(super.result);
  ForumMultipartRequest? multipartRequest;
  final multipartResult = ForumTransportSuccess(
    ForumMultipartResponse(
      uri: _apiUri,
      statusCode: 200,
      headers: const {},
      body: 'fixture-upload',
    ),
  );

  @override
  Future<ForumTransportResult<ForumMultipartResponse>> sendMultipart(
    ForumMultipartRequest request,
  ) async {
    multipartRequest = request;
    return multipartResult;
  }
}

final class _FullNetwork extends _ResourceNetwork
    implements ForumMultipartClient {
  _FullNetwork(super.result);
  ForumMultipartRequest? multipartRequest;
  final multipartResult = ForumTransportSuccess(
    ForumMultipartResponse(
      uri: _apiUri,
      statusCode: 200,
      headers: const {},
      body: 'fixture-upload',
    ),
  );

  @override
  Future<ForumTransportResult<ForumMultipartResponse>> sendMultipart(
    ForumMultipartRequest request,
  ) async {
    multipartRequest = request;
    return multipartResult;
  }
}

final class _WafHttpAdapter implements HttpClientAdapter {
  int requests = 0;
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody.fromString(
      jsonEncode(_apiBody()),
      requests == 1 ? 405 : 200,
      headers: const {
        'content-type': <String>['application/json'],
      },
    );
  }
}

final class _VerifiedWaf implements ForumWafRecoveryDelegate {
  int calls = 0;
  @override
  Future<ForumWafRecoveryResult> recover(
    ForumWafRecoveryRequest request,
  ) async {
    calls++;
    return ForumWafRecoveryResult.verified;
  }
}
