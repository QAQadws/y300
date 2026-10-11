import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  late _Network network;
  late YamiboForumClient client;

  setUp(() {
    network = _Network();
    client = _builder(network).buildStandardClient();
  });

  test('standard facade installs a fresh non-consuming v1 probe', () async {
    final result = await client.loadMessageAttention(_query);
    final request = network.requests.single;
    expect(request.method, ForumRequestMethod.get);
    expect(request.uri.queryParameters, {
      'module': 'forumindex',
      'version': '1',
      'checknotice': '1',
    });
    expect(request.context.pageKind, 'message.attention.probe');
    expect(request.context.silent, isTrue);
    expect(request.responseType, ForumResponseType.json);
    expect(request.body, isNull);
    expect(request.headers['User-Agent'], _config.effectiveApiUserAgent);
    final success =
        result
            as DataReadSuccess<
              ForumMessageAttentionObservation,
              ForumMessageAttentionReadCapabilities
            >;
    expect(success.metadata.origin, DataReadOrigin.network);
    expect(success.metadata.freshness, DataReadFreshness.current);
    expect(success.data.viewerUserId, '10');
    expect(success.data.combined, ForumMessageAttentionState.absent);
    expect(
      success.capabilities.values.supports(
        ForumMessageAttentionCapability.notificationCount,
      ),
      isTrue,
    );
    expect(client.messageAttention, isNotNull);
    await client.loadMessageAttention(_query);
    expect(network.requests, hasLength(2));
  });

  test(
    'partial indicators retain unknown fields and read capabilities',
    () async {
      network.body = _envelope(notice: {'newpm': '2'});
      final result = await client.loadMessageAttention(_query);
      final success =
          result
              as DataReadSuccess<
                ForumMessageAttentionObservation,
                ForumMessageAttentionReadCapabilities
              >;
      expect(success.data.privateMessages, ForumMessageAttentionState.present);
      expect(success.data.notifications, ForumMessageAttentionState.unknown);
      expect(success.data.notificationCount, isNull);
      expect(
        success.capabilities.values.supportOf(
          ForumMessageAttentionCapability.notificationArrival,
        ),
        DataCapabilitySupport.unknown,
      );
      expect(
        client.messageAttention!.capabilities.values.supports(
          ForumMessageAttentionCapability.notificationArrival,
        ),
        isTrue,
      );
    },
  );

  test(
    'the factory exposes the probe through the neutral repository port',
    () async {
      final repository = ForumClientAdapterFactory(
        config: _config,
        network: network,
      ).createMessageAttention();
      expect((await repository.load(_query)).isSuccess, isTrue);
      expect(network.requests, hasLength(1));
    },
  );

  test(
    'the explicit probe never also publishes through the passive observer',
    () async {
      final observer = _Observer();
      client = _builder(network, observer: observer).buildStandardClient();
      expect((await client.loadMessageAttention(_query)).isSuccess, isTrue);
      expect(observer.captures, 0);
      expect(observer.deliveries, 0);
      final request = network.requests.single;
      await client.network.send(
        ForumRequest(
          method: request.method,
          uri: request.uri,
          context: const ForumRequestContext(operation: 'forumindex'),
          responseType: request.responseType,
        ),
      );
      expect(observer.captures, 1);
      expect(observer.deliveries, 1);
    },
  );

  test(
    'a source override and an omitted advanced source remain explicit',
    () async {
      final override = _Override();
      client = _builder(network).buildStandardClient(
        sourceOverrides: ForumClientSourcePlan(messageAttention: override),
      );
      final cancellation = ForumRequestCancellation();
      final query = ForumMessageAttentionQuery(
        expectedUserId: '10',
        cancellation: cancellation,
      );
      expect((await client.loadMessageAttention(query)).isSuccess, isTrue);
      expect(identical(override.query, query), isTrue);
      expect(identical(client.messageAttention, override), isTrue);
      expect(network.requests, isEmpty);
      final advanced = YamiboForumClient(config: _config, network: network);
      final result = await advanced.loadMessageAttention(query);
      expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
      expect(network.requests, isEmpty);
    },
  );

  for (final body in [
    '\uFEFF${jsonEncode(_envelope())}',
    ' ï»¿ ${jsonEncode(_envelope())}',
  ]) {
    test('the established JSON BOM forms are accepted', () async {
      network.body = body;
      expect((await client.loadMessageAttention(_query)).isSuccess, isTrue);
    });
  }

  for (final viewer in <Object?>[null, '0', '11', ' 10', '010', 10.0, true]) {
    test('unverified viewer $viewer is never an inactive hint', () async {
      network.body = _envelope(viewer: viewer);
      final result = await client.loadMessageAttention(_query);
      expect(result.isFailure, isTrue);
      expect(
        result.failureOrNull!.diagnosticMessage,
        'message_attention_probe_unverified',
      );
    });
  }

  test('content-owner space.uid cannot replace a missing viewer', () async {
    final envelope = _envelope(viewer: null);
    (envelope['Variables'] as Map<String, Object?>)['space'] = {'uid': '10'};
    network.body = envelope;
    expect((await client.loadMessageAttention(_query)).isFailure, isTrue);
  });

  for (final version in <Object?>[null, '', '4', ' 1', 1.0, true]) {
    test('unknown or conflicting body version $version is rejected', () async {
      network.body = {..._envelope(), 'Version': version};
      expect((await client.loadMessageAttention(_query)).isFailure, isTrue);
    });
  }

  for (final body in <Object?>[
    '<html>private payload</html>',
    '{',
    {'Version': '1', 'Variables': 'invalid'},
    {
      ..._envelope(),
      'Message': {'messageval': 'to_login', 'messagestr': 'private payload'},
    },
    {..._envelope(), 'Message': 'private payload'},
    _envelope(notice: {}),
    _envelope(notice: {'newpm': 'bad', 'newprompt': '-1', 'newmypost': null}),
  ]) {
    test(
      'malformed and error responses never create a zero observation',
      () async {
        network.body = body;
        final result = await client.loadMessageAttention(_query);
        expect(result.failureOrNull!.kind, DataReadFailureKind.parse);
        expect(
          result.failureOrNull!.diagnosticMessage,
          isNot(contains('private payload')),
        );
      },
    );
  }

  for (final status in <int?>[null, 0, 302, 304, 401, 403, 500]) {
    test('HTTP $status is not a fresh successful probe', () async {
      network.status = status;
      expect((await client.loadMessageAttention(_query)).isFailure, isTrue);
    });
  }

  for (final suffix in [
    '?module=forumindex&version=4&checknotice=1',
    '?module=forumindex&version=1',
    '?module=forumindex&version=1&checknotice=0',
    '?module=viewthread&version=1&checknotice=1',
    '?module=mypm&version=1&checknotice=1',
    '?module=forumindex&version=1&checknotice=1&op=delete',
    '?module=forumindex&version=1&checknotice=1&checknotice=1',
    '?module=forumindex&version=1&checknotice=1#fragment',
    '?module=forumindex&version=1&checknotice=%FF',
  ]) {
    test('redirected or ambiguous query is rejected: $suffix', () async {
      network.responseUri = Uri.parse(
        'https://forum.example.test/api/mobile/index.php$suffix',
      );
      expect((await client.loadMessageAttention(_query)).isFailure, isTrue);
    });
  }

  for (final uri in [
    'https://other.example.test/api/mobile/index.php?module=forumindex&version=1&checknotice=1',
    'http://forum.example.test/api/mobile/index.php?module=forumindex&version=1&checknotice=1',
    'https://forum.example.test/forum.php?module=forumindex&version=1&checknotice=1',
    'https://user@forum.example.test/api/mobile/index.php?module=forumindex&version=1&checknotice=1',
  ]) {
    test('wrong final origin or path is rejected: $uri', () async {
      network.responseUri = Uri.parse(uri);
      expect((await client.loadMessageAttention(_query)).isFailure, isTrue);
    });
  }

  for (final viewer in ['', '0', '010', '10&uid=11', '9007199254740992']) {
    test('invalid requested viewer $viewer fails before sending', () async {
      final result = await client.loadMessageAttention(
        ForumMessageAttentionQuery(expectedUserId: viewer),
      );
      expect(result.failureOrNull!.kind, DataReadFailureKind.business);
      expect(network.requests, isEmpty);
    });
  }

  test(
    'missing or foreign API origin fails without an extra transport',
    () async {
      for (final apiOrigin in <Uri?>[
        null,
        Uri.parse('https://other.example.test/api/mobile/index.php'),
      ]) {
        final unavailable = YamiboForumClientBuilder(
          config: ForumClientConfig(
            siteOrigin: _config.siteOrigin,
            apiOrigin: apiOrigin,
            userAgent: 'fixture',
          ),
          network: network,
        ).buildStandardClient();
        expect(
          (await unavailable.loadMessageAttention(_query)).failureOrNull!.kind,
          DataReadFailureKind.unsupported,
        );
      }
      expect(network.requests, isEmpty);
    },
  );

  test('cancelled probes neither send nor return a late observation', () async {
    final cancelled = ForumRequestCancellation()..cancel();
    expect(
      (await client.loadMessageAttention(
        ForumMessageAttentionQuery(
          expectedUserId: '10',
          cancellation: cancelled,
        ),
      )).failureOrNull!.kind,
      DataReadFailureKind.cancelled,
    );
    expect(network.requests, isEmpty);
    final pending = Completer<void>();
    network.pending = pending;
    final cancellation = ForumRequestCancellation();
    final result = client.loadMessageAttention(
      ForumMessageAttentionQuery(
        expectedUserId: '10',
        cancellation: cancellation,
      ),
    );
    expect(
      identical(network.requests.single.cancellation, cancellation),
      isTrue,
    );
    cancellation.cancel();
    pending.complete();
    expect((await result).failureOrNull!.kind, DataReadFailureKind.cancelled);
  });

  test(
    'transport failures retain their category without exposing payloads',
    () async {
      network.failure = const ForumTransportFailure(
        kind: ForumTransportFailureKind.timeout,
        code: 'private payload',
        statusCode: 504,
      );
      final result = await client.loadMessageAttention(_query);
      expect(result.failureOrNull!.kind, DataReadFailureKind.timeout);
      expect(result.failureOrNull!.statusCode, 504);
      expect(
        result.failureOrNull!.diagnosticMessage,
        'message_attention_probe_transport_failed',
      );
    },
  );
}

const _query = ForumMessageAttentionQuery(expectedUserId: '10');
final _config = ForumClientConfig(
  siteOrigin: Uri.parse('https://forum.example.test'),
  apiOrigin: Uri.parse('https://forum.example.test/api/mobile/index.php'),
  userAgent: 'fixture',
  apiUserAgent: 'fixture-api',
);

YamiboForumClientBuilder _builder(
  _Network network, {
  ForumMessageAttentionObserver? observer,
}) => YamiboForumClientBuilder(
  config: _config,
  network: network,
  messageAttentionObserver: observer,
);

Map<String, Object?> _envelope({
  Object? viewer = '10',
  Map<String, Object?> notice = const {
    'newpm': '0',
    'newprompt': '0',
    'newmypost': '0',
  },
}) => {
  'Version': '1',
  'Variables': {'member_uid': viewer, 'notice': notice},
};

final class _Network implements ForumClientNetwork {
  final requests = <ForumRequest>[];
  Object? body = _envelope();
  int? status = 200;
  Uri? responseUri;
  Completer<void>? pending;
  ForumTransportFailure? failure;

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    await pending?.future;
    if (failure case final failure?) return ForumTransportError(failure);
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: responseUri ?? request.uri,
        statusCode: status,
        headers: const {},
        body: body,
      ),
    );
  }
}

final class _Observer implements ForumMessageAttentionObserver {
  int captures = 0;
  int deliveries = 0;
  @override
  ForumMessageAttentionRequestContext captureRequest() =>
      ForumMessageAttentionRequestContext(
        viewerUserId: '10',
        requestSequence: ++captures,
        ownerToken: 'fixture',
      );
  @override
  void onObservation(
    ForumMessageAttentionObservation observation, {
    required ForumMessageAttentionRequestContext context,
  }) {
    deliveries++;
  }
}

final class _Override implements ForumMessageAttentionRepository {
  ForumMessageAttentionQuery? query;
  @override
  ForumMessageAttentionSourceCapabilities get capabilities =>
      ForumMessageAttentionSourceCapabilities(
        values: DataCapabilitySet.supported(
          ForumMessageAttentionCapability.values,
        ),
      );
  @override
  Future<
    DataReadResult<
      ForumMessageAttentionObservation,
      ForumMessageAttentionReadCapabilities
    >
  >
  load(ForumMessageAttentionQuery query) async {
    this.query = query;
    return DataReadSuccess(
      data: const ForumMessageAttentionObservation(
        viewerUserId: '10',
        source: ForumMessageAttentionSource.api,
        privateMessages: ForumMessageAttentionState.absent,
      ),
      capabilities: ForumMessageAttentionReadCapabilities(
        values: capabilities.values,
      ),
      metadata: const DataReadMetadata.network(),
    );
  }
}
