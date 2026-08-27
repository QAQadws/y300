import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  group('Discuz favorite commands', () {
    test('forum favorite is submitted and confirmed by fid', () async {
      final network = _QueueNetwork(<Object?>[
        _message('favorite_do_success'),
        _favoriteForums(<Map<String, Object?>>[
          <String, Object?>{
            'id': '30',
            'favid': '701',
            'title': 'Fixture forum',
          },
        ]),
      ]);
      final command = _commands(network).$1;

      final result = await command.execute(
        const SetForumFavoriteRequest(
          fid: '30',
          targetState: FavoriteTargetState.favorited,
        ),
      );

      expect(result, isA<DataCommandApplied<ForumFavoriteReceipt>>());
      final receipt = result.receiptOrNull!;
      expect(receipt.remoteFavoriteId, '701');
      expect(receipt.disposition, FavoriteMutationDisposition.changed);
      final mutation = network.requests.first;
      expect(mutation.uri.queryParameters, containsPair('module', 'favforum'));
      expect(mutation.uri.queryParameters, containsPair('version', '4'));
      expect(mutation.body, containsPair('id', '30'));
      expect(mutation.body, containsPair('favoritesubmit', '1'));
    });

    test(
      'forum unfavorite resolves and verifies favid before deleting',
      () async {
        final network = _QueueNetwork(<Object?>[
          _favoriteForums(<Map<String, Object?>>[
            <String, Object?>{
              'id': '30',
              'favid': '701',
              'title': 'Fixture forum',
            },
          ]),
          _message('do_success'),
          _favoriteForums(const <Map<String, Object?>>[]),
        ]);
        final command = _commands(network).$1;

        final result = await command.execute(
          const SetForumFavoriteRequest(
            fid: '30',
            targetState: FavoriteTargetState.unfavorited,
            knownRemoteFavoriteId: '701',
          ),
        );

        expect(result, isA<DataCommandApplied<ForumFavoriteReceipt>>());
        final mutation = network.requests[1];
        expect(
          mutation.uri.queryParameters,
          containsPair('module', 'favthread'),
        );
        expect(mutation.uri.queryParameters, containsPair('op', 'delete'));
        expect(mutation.uri.queryParameters, containsPair('favid', '701'));
        expect(mutation.uri.queryParameters, isNot(contains('id')));
      },
    );

    test(
      'forum unfavorite is idempotent when directory proves absence',
      () async {
        final network = _QueueNetwork(<Object?>[
          _favoriteForums(const <Map<String, Object?>>[]),
        ]);

        final result = await _commands(network).$1.execute(
          const SetForumFavoriteRequest(
            fid: '30',
            targetState: FavoriteTargetState.unfavorited,
          ),
        );

        expect(result, isA<DataCommandApplied<ForumFavoriteReceipt>>());
        expect(
          result.receiptOrNull!.disposition,
          FavoriteMutationDisposition.alreadyApplied,
        );
        expect(network.requests, hasLength(1));
      },
    );

    test('forum favid mismatch is rejected before mutation', () async {
      final network = _QueueNetwork(<Object?>[
        _favoriteForums(<Map<String, Object?>>[
          <String, Object?>{
            'id': '30',
            'favid': '701',
            'title': 'Fixture forum',
          },
        ]),
      ]);

      final result = await _commands(network).$1.execute(
        const SetForumFavoriteRequest(
          fid: '30',
          targetState: FavoriteTargetState.unfavorited,
          knownRemoteFavoriteId: '999',
        ),
      );

      expect(result, isA<DataCommandNotSent<ForumFavoriteReceipt>>());
      expect(
        result.failureOrNull?.code,
        'favorite_forum_remote_identity_mismatch',
      );
      expect(network.requests, hasLength(1));
    });

    test(
      'thread favorite uses tid and confirms the returned directory',
      () async {
        final network = _QueueNetwork(<Object?>[
          _message('favorite_do_success'),
          _favoriteThreads(<Map<String, Object?>>[
            <String, Object?>{
              'id': '10001',
              'favid': '801',
              'title': 'Fixture thread',
            },
          ]),
        ]);
        final command = _commands(network).$2;

        final result = await command.execute(
          const SetThreadFavoriteRequest(
            tid: '10001',
            targetState: FavoriteTargetState.favorited,
          ),
        );

        expect(result, isA<DataCommandApplied<ThreadFavoriteReceipt>>());
        expect(result.receiptOrNull!.remoteFavoriteId, '801');
        expect(network.requests.first.body, containsPair('id', '10001'));
        expect(
          network.requests.first.headers['Referer'],
          'https://fixture.example/forum.php?mod=viewthread&tid=10001&mobile=2',
        );
      },
    );

    test('thread unfavorite deletes by tid rather than favid', () async {
      final network = _QueueNetwork(<Object?>[
        _message('do_success'),
        _favoriteThreads(const <Map<String, Object?>>[]),
      ]);

      final result = await _commands(network).$2.execute(
        const SetThreadFavoriteRequest(
          tid: '10001',
          targetState: FavoriteTargetState.unfavorited,
        ),
      );

      expect(result, isA<DataCommandApplied<ThreadFavoriteReceipt>>());
      final mutation = network.requests.first;
      expect(mutation.uri.queryParameters, containsPair('id', '10001'));
      expect(mutation.uri.queryParameters, containsPair('type', 'thread'));
      expect(mutation.uri.queryParameters, isNot(contains('favid')));
    });

    test(
      'accepted mutation with mismatched readback is outcome unknown',
      () async {
        final network = _QueueNetwork(<Object?>[
          _message('favorite_do_success'),
          _favoriteThreads(const <Map<String, Object?>>[]),
        ]);

        final result = await _commands(network).$2.execute(
          const SetThreadFavoriteRequest(
            tid: '10001',
            targetState: FavoriteTargetState.favorited,
          ),
        );

        expect(result, isA<DataCommandOutcomeUnknown<ThreadFavoriteReceipt>>());
        expect(result.failureOrNull?.code, 'favorite_thread_state_unconfirmed');
        expect(network.requests, hasLength(2));
      },
    );

    test('post timeout is outcome unknown and is not retried', () async {
      final network = _QueueNetwork(<Object?>[
        const ForumTransportFailure(
          kind: ForumTransportFailureKind.timeout,
          code: 'fixture_timeout',
        ),
      ]);

      final result = await _commands(network).$2.execute(
        const SetThreadFavoriteRequest(
          tid: '10001',
          targetState: FavoriteTargetState.favorited,
        ),
      );

      expect(result, isA<DataCommandOutcomeUnknown<ThreadFavoriteReceipt>>());
      expect(result.failureOrNull?.kind, DataCommandFailureKind.timeout);
      expect(
        result.failureOrNull?.retryPolicy,
        DataCommandRetryPolicy.explicitOnly,
      );
      expect(network.requests, hasLength(1));
    });

    test('readback failure after accepted post is outcome unknown', () async {
      final network = _QueueNetwork(<Object?>[
        _message('favorite_do_success'),
        const ForumTransportFailure(
          kind: ForumTransportFailureKind.network,
          code: 'fixture_readback_failed',
        ),
      ]);

      final result = await _commands(network).$2.execute(
        const SetThreadFavoriteRequest(
          tid: '10001',
          targetState: FavoriteTargetState.favorited,
        ),
      );

      expect(result, isA<DataCommandOutcomeUnknown<ThreadFavoriteReceipt>>());
      expect(result.failureOrNull?.code, 'fixture_readback_failed');
      expect(network.requests, hasLength(2));
    });

    test('server rejection exposes only a stable code', () async {
      final network = _QueueNetwork(<Object?>[
        _message(
          'permission_denied',
          text: 'Cookie=private; formhash=secret; password=secret',
        ),
      ]);

      final result = await _commands(network).$2.execute(
        const SetThreadFavoriteRequest(
          tid: '10001',
          targetState: FavoriteTargetState.favorited,
        ),
      );

      expect(result, isA<DataCommandRejected<ThreadFavoriteReceipt>>());
      expect(result.failureOrNull?.code, 'permission_denied');
      expect(result.failureOrNull?.diagnosticMessage, 'permission_denied');
      expect(result.failureOrNull.toString(), isNot(contains('secret')));
    });

    test('pre-cancelled request is not sent', () async {
      final network = _QueueNetwork(const <Object?>[]);
      final cancellation = ForumRequestCancellation()..cancel();

      final result = await _commands(network).$1.execute(
        SetForumFavoriteRequest(
          fid: '30',
          targetState: FavoriteTargetState.favorited,
          cancellation: cancellation,
        ),
      );

      expect(result, isA<DataCommandNotSent<ForumFavoriteReceipt>>());
      expect(result.failureOrNull?.kind, DataCommandFailureKind.cancelled);
      expect(network.requests, isEmpty);
    });

    test('invalid identity does not request formhash or mutate', () async {
      final network = _QueueNetwork(const <Object?>[]);

      final result = await _commands(network).$2.execute(
        const SetThreadFavoriteRequest(
          tid: 'invalid',
          targetState: FavoriteTargetState.favorited,
        ),
      );

      expect(result, isA<DataCommandNotSent<ThreadFavoriteReceipt>>());
      expect(network.requests, isEmpty);
    });
  });
}

(FavoriteForumCommand, FavoriteThreadCommand) _commands(_QueueNetwork network) {
  final factory = ForumClientAdapterFactory(config: _config, network: network);
  const formhash = _FixtureFormhashProvider();
  final forumDirectory = factory.createFavoriteForumDirectory();
  final threadDirectory = factory.createFavoriteThreadDirectory();
  return (
    factory.createFavoriteForumCommand(
      formhash: formhash,
      directory: forumDirectory,
    ),
    factory.createFavoriteThreadCommand(
      formhash: formhash,
      directory: threadDirectory,
    ),
  );
}

Map<String, Object?> _message(String code, {String text = 'fixture-message'}) =>
    <String, Object?>{
      'Variables': <String, Object?>{},
      'Message': <String, Object?>{'messageval': code, 'messagestr': text},
    };

Map<String, Object?> _favoriteForums(List<Map<String, Object?>> items) =>
    <String, Object?>{
      'Variables': <String, Object?>{'list': items},
    };

Map<String, Object?> _favoriteThreads(List<Map<String, Object?>> items) =>
    <String, Object?>{
      'Variables': <String, Object?>{
        'list': items,
        'perpage': '20',
        'count': items.length.toString(),
      },
    };

final _config = ForumClientConfig(
  siteOrigin: Uri.parse('https://fixture.example/'),
  apiOrigin: Uri.parse('https://fixture.example/api/mobile/index.php'),
  desktopUserAgent: 'fixture-agent',
  userAgent: 'fixture-agent',
);

final class _FixtureFormhashProvider implements ForumFormhashProvider {
  const _FixtureFormhashProvider();

  @override
  Future<ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
    ForumRequestCancellation? cancellation,
  }) async => const ForumFormhashSuccess('fixture-formhash');
}

final class _QueueNetwork implements ForumClientNetwork {
  _QueueNetwork(List<Object?> responses) : _responses = List.of(responses);

  final List<Object?> _responses;
  final List<ForumRequest> requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    if (_responses.isEmpty) {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.network,
          code: 'unexpected_request',
        ),
      );
    }
    final body = _responses.removeAt(0);
    if (body is ForumTransportFailure) {
      return ForumTransportError(body);
    }
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const <String, List<String>>{},
        body: body,
      ),
    );
  }
}
