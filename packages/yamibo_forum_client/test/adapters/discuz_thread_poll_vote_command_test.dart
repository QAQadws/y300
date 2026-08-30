import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://example.test'),
    apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
    userAgent: 'mobile-html-test',
    apiUserAgent: 'mobile-api-test',
  );

  test('submits ordered duplicate fields to the fixed v2 API', () async {
    final network = _QueueNetwork(<Object?>[_envelope('thread_poll_succeed')]);
    final command = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createThreadPollVote(const _FixtureFormhashProvider());

    final result = await command.execute(
      const ThreadPollVoteSubmission(
        fid: '30',
        tid: '10001',
        optionIds: <String>['7', '9'],
      ),
    );

    expect(result, isA<DataCommandApplied<ThreadPollVoteReceipt>>());
    expect(result.receiptOrNull!.optionIds, <String>['7', '9']);
    final request = network.requests.single;
    expect(request.uri.path, '/api/mobile/index.php');
    expect(request.uri.queryParameters, containsPair('module', 'pollvote'));
    expect(request.uri.queryParameters, containsPair('version', '2'));
    expect(request.uri.queryParameters, containsPair('pollsubmit', 'yes'));
    expect(request.uri.queryParameters, containsPair('fid', '30'));
    expect(request.uri.queryParameters, containsPair('tid', '10001'));
    expect(request.headers['User-Agent'], 'mobile-api-test');
    final fields = request.body as ForumFormFields;
    expect(fields.entries.map((entry) => (entry.key, entry.value)), <Object>[
      ('formhash', 'fixture-formhash'),
      ('pollanswers[]', '7'),
      ('pollanswers[]', '9'),
    ]);
    expect(
      fields.encode(),
      'formhash=fixture-formhash&pollanswers%5B%5D=7&pollanswers%5B%5D=9',
    );
  });

  test(
    'normalizes the mobile namespace before exact success matching',
    () async {
      final command = ForumClientAdapterFactory(
        config: config,
        network: _QueueNetwork(<Object?>[
          _envelope('mobile:thread_poll_succeed'),
        ]),
      ).createThreadPollVote(const _FixtureFormhashProvider());

      final result = await command.execute(_validSubmission);

      expect(result, isA<DataCommandApplied<ThreadPollVoteReceipt>>());
    },
  );

  test('does not accept a similar but unproved success code', () async {
    final command = ForumClientAdapterFactory(
      config: config,
      network: _QueueNetwork(<Object?>[_envelope('thread_poll_success')]),
    ).createThreadPollVote(const _FixtureFormhashProvider());

    final result = await command.execute(_validSubmission);

    expect(result, isA<DataCommandOutcomeUnknown<ThreadPollVoteReceipt>>());
    expect(
      result.failureOrNull!.code,
      'thread_poll_vote_response_unrecognized',
    );
  });

  test('does not accept success evidence carrying a login suffix', () async {
    final command = ForumClientAdapterFactory(
      config: config,
      network: _QueueNetwork(<Object?>[_envelope('thread_poll_succeed//1')]),
    ).createThreadPollVote(const _FixtureFormhashProvider());

    final result = await command.execute(_validSubmission);

    expect(result, isA<DataCommandOutcomeUnknown<ThreadPollVoteReceipt>>());
  });

  test('rejects every explicit Discuz poll business code', () async {
    const expected = <String, DataCommandFailureKind>{
      'group_nopermission': DataCommandFailureKind.permissionDenied,
      'thread_poll_closed': DataCommandFailureKind.validation,
      'thread_poll_invalid': DataCommandFailureKind.validation,
      'poll_not_found': DataCommandFailureKind.validation,
      'poll_overdue': DataCommandFailureKind.validation,
      'poll_choose_most': DataCommandFailureKind.validation,
      'thread_poll_voted': DataCommandFailureKind.validation,
      'parameters_error': DataCommandFailureKind.validation,
      'submit_invalid': DataCommandFailureKind.staleFormhash,
    };
    for (final entry in expected.entries) {
      final command = ForumClientAdapterFactory(
        config: config,
        network: _QueueNetwork(<Object?>[_envelope(entry.key)]),
      ).createThreadPollVote(const _FixtureFormhashProvider());

      final result = await command.execute(_validSubmission);

      expect(
        result,
        isA<DataCommandRejected<ThreadPollVoteReceipt>>(),
        reason: entry.key,
      );
      expect(result.failureOrNull!.kind, entry.value, reason: entry.key);
      expect(result.failureOrNull!.code, entry.key, reason: entry.key);
    }
  });

  test('login suffix is preserved as an authentication rejection', () async {
    final command = ForumClientAdapterFactory(
      config: config,
      network: _QueueNetwork(<Object?>[
        _envelope('mobile:thread_poll_voted//1'),
      ]),
    ).createThreadPollVote(const _FixtureFormhashProvider());

    final result = await command.execute(_validSubmission);

    expect(result, isA<DataCommandRejected<ThreadPollVoteReceipt>>());
    expect(result.failureOrNull!.kind, DataCommandFailureKind.unauthenticated);
    expect(result.failureOrNull!.code, 'thread_poll_voted');
  });

  test('invalid input and unavailable formhash never send mutation', () async {
    final network = _QueueNetwork(const <Object?>[]);
    final invalidCommand = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createThreadPollVote(const _FixtureFormhashProvider());

    final invalid = await invalidCommand.execute(
      const ThreadPollVoteSubmission(
        fid: '30',
        tid: '10001',
        optionIds: <String>['7', '7'],
      ),
    );
    expect(invalid, isA<DataCommandNotSent<ThreadPollVoteReceipt>>());
    expect(network.requests, isEmpty);

    final missingHash = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createThreadPollVote(const _FixtureFormhashProvider(''));
    final noHash = await missingHash.execute(_validSubmission);
    expect(noHash, isA<DataCommandNotSent<ThreadPollVoteReceipt>>());
    expect(noHash.failureOrNull!.kind, DataCommandFailureKind.staleFormhash);
    expect(network.requests, isEmpty);
  });

  test(
    'transport and malformed/version-mismatched responses stay unknown',
    () async {
      final transportNetwork = _QueueNetwork(const <Object?>[
        ForumTransportFailure(
          kind: ForumTransportFailureKind.timeout,
          code: 'timeout',
        ),
      ]);
      final transportCommand = ForumClientAdapterFactory(
        config: config,
        network: transportNetwork,
      ).createThreadPollVote(const _FixtureFormhashProvider());
      final transport = await transportCommand.execute(_validSubmission);
      expect(
        transport,
        isA<DataCommandOutcomeUnknown<ThreadPollVoteReceipt>>(),
      );
      expect(transport.failureOrNull!.kind, DataCommandFailureKind.timeout);

      for (final response in <Object?>[
        <String, Object?>{
          'Version': '1',
          'Variables': const <String, Object?>{},
          'Message': const <String, Object?>{
            'messageval': 'thread_poll_succeed',
          },
        },
        const <String, Object?>{
          'Version': '2',
          'Variables': <String, Object?>{},
        },
      ]) {
        final command = ForumClientAdapterFactory(
          config: config,
          network: _QueueNetwork(<Object?>[response]),
        ).createThreadPollVote(const _FixtureFormhashProvider());
        final result = await command.execute(_validSubmission);
        expect(result, isA<DataCommandOutcomeUnknown<ThreadPollVoteReceipt>>());
      }
    },
  );

  test('legacy snapshot action and formhash are ignored', () {
    const codec = ThreadDetailSnapshotCodec();
    final decoded = codec.decode(<String, Object?>{
      'tid': '10001',
      'fid': '30',
      'posts': <Object?>[
        <String, Object?>{
          'pid': '20001',
          'poll': <String, Object?>{
            'isMultipleChoice': false,
            'canVote': true,
            'summary': 'fixture poll',
            'actionUrl': 'https://private.invalid/vote',
            'formHash': 'private-formhash',
            'options': <Object?>[
              <String, Object?>{'id': '7', 'label': 'A'},
            ],
          },
        },
      ],
    });

    final dynamic poll = decoded.posts.single.poll;
    expect(poll.actionUrl, isNull);
    expect(poll.formHash, isNull);
    final encoded = codec.encode(decoded).toString();
    expect(encoded, isNot(contains('actionUrl')));
    expect(encoded, isNot(contains('formHash')));
    expect(encoded, isNot(contains('private-formhash')));
  });
}

const _validSubmission = ThreadPollVoteSubmission(
  fid: '30',
  tid: '10001',
  optionIds: <String>['7'],
);

Map<String, Object?> _envelope(String code) => <String, Object?>{
  'Version': '2',
  'Variables': const <String, Object?>{},
  'Message': <String, Object?>{
    'messageval': code,
    'messagestr': 'private server text',
  },
};

final class _QueueNetwork implements ForumClientNetwork {
  _QueueNetwork(Iterable<Object?> responses)
    : responses = List<Object?>.of(responses);

  final List<Object?> responses;
  final List<ForumRequest> requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    final response = responses.removeAt(0);
    if (response is ForumTransportFailure) {
      return ForumTransportError(response);
    }
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const <String, List<String>>{},
        body: response,
      ),
    );
  }
}

final class _FixtureFormhashProvider implements ForumFormhashProvider {
  const _FixtureFormhashProvider([this.value = 'fixture-formhash']);

  final String value;

  @override
  Future<ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
    ForumRequestCancellation? cancellation,
  }) async => ForumFormhashSuccess(value);
}
