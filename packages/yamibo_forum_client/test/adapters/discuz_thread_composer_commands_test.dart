import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  group('DiscuzThreadCreationAdapter', () {
    test('prepares forum identity, types, limits, and opaque token', () async {
      final network = _QueueNetwork(<Object?>[_preparationEnvelope]);
      final adapter = _factory(
        network,
      ).createThreadCreation(const _FixtureFormhashProvider());

      final result = await adapter.preparation.load(
        const ThreadCreationPreparationRequest(fid: '30'),
      );

      final preparation = result.dataOrNull!;
      expect(preparation.fid, '30');
      expect(preparation.forumName, 'Fixture forum');
      expect(preparation.threadTypes.map((item) => item.id), <String>[
        '101',
        '102',
      ]);
      expect(preparation.typeRequired, isTrue);
      expect(preparation.maxSubjectLength, 80);
      expect(preparation.maxMessageLength, 10000);
      expect(preparation.token.toString(), contains('redacted'));
      expect(
        network.requests.single.uri.queryParameters,
        containsPair('page', '1'),
      );
    });

    test(
      'submits all supported fields and returns no raw server text',
      () async {
        final network = _QueueNetwork(<Object?>[
          _preparationEnvelope,
          _commandEnvelope(
            code: 'post_newthread_succeed',
            tid: '40001',
            pid: '50001',
          ),
        ]);
        final adapter = _factory(
          network,
        ).createThreadCreation(const _FixtureFormhashProvider());
        final preparation = (await adapter.preparation.load(
          const ThreadCreationPreparationRequest(fid: '30'),
        )).dataOrNull!;

        final result = await adapter.command.execute(
          ThreadCreationSubmission(
            preparation: preparation,
            subject: 'Fixture subject',
            message: 'Fixture [attach]60001[/attach]',
            typeId: '101',
            useSignature: true,
            notifyAuthor: true,
            disableBbCode: false,
            disableSmileys: false,
            disableUrlParsing: false,
            attachmentIds: const <String>['60001'],
            tags: const <String>['fixture'],
            kind: ThreadCreationKind.poll,
            poll: const ThreadPollSubmission(
              options: <String>['A', 'B'],
              maximumChoices: 1,
              expirationDays: 0,
              publicVoters: true,
              resultsAfterVote: true,
            ),
          ),
        );

        expect(result, isA<DataCommandApplied<ThreadCreationReceipt>>());
        expect(result.receiptOrNull!.tid, '40001');
        expect(
          result.receiptOrNull!.readAccess.kind,
          ThreadReadAccessEvidenceKind.unrestricted,
        );
        final form = network.requests.last.body!;
        expect(form, containsPair('readperm', '0'));
        expect(form, containsPair('special', '1'));
        expect(form, containsPair('tags', 'fixture'));
        expect(form, containsPair('polloptions', 'A\nB'));
        expect(form, containsPair('attachnew[60001][description]', ''));
        expect(result.toString(), isNot(contains('private server text')));
      },
    );

    test(
      'non-zero readperm is read back without weakening primary proof',
      () async {
        final network = _QueueNetwork(<Object?>[
          _preparationEnvelope,
          _commandEnvelope(
            code: 'post_newthread_mod_succeed',
            tid: '40001',
            pid: '50001',
          ),
          <String, Object?>{
            'Version': '4',
            'Variables': <String, Object?>{
              'thread': <String, Object?>{'tid': '40001', 'readperm': '0'},
            },
          },
        ]);
        final adapter = _factory(
          network,
        ).createThreadCreation(const _FixtureFormhashProvider());
        final preparation = (await adapter.preparation.load(
          const ThreadCreationPreparationRequest(fid: '30'),
        )).dataOrNull!;

        final result = await adapter.command.execute(
          _ordinarySubmission(preparation, minimumReadAccess: 40),
        );

        expect(result, isA<DataCommandApplied<ThreadCreationReceipt>>());
        expect(
          result.receiptOrNull!.publicationState,
          ThreadPublicationState.pendingModeration,
        );
        expect(
          result.receiptOrNull!.readAccess.kind,
          ThreadReadAccessEvidenceKind.serverAdjusted,
        );
        expect(result.receiptOrNull!.readAccess.actual, 0);
        expect(
          network.requests.last.uri.queryParameters['module'],
          'viewthread',
        );
      },
    );

    test('invalid readperm is rejected before a mutation request', () async {
      final network = _QueueNetwork(<Object?>[_preparationEnvelope]);
      final adapter = _factory(
        network,
      ).createThreadCreation(const _FixtureFormhashProvider());
      final preparation = (await adapter.preparation.load(
        const ThreadCreationPreparationRequest(fid: '30'),
      )).dataOrNull!;

      final result = await adapter.command.execute(
        _ordinarySubmission(preparation, minimumReadAccess: 256),
      );

      expect(result, isA<DataCommandNotSent<ThreadCreationReceipt>>());
      expect(network.requests, hasLength(1));
    });
  });

  group('DiscuzThreadReplyAdapter', () {
    test(
      'ordinary reply obtains formhash and requires exact receipt identity',
      () async {
        final network = _QueueNetwork(<Object?>[
          _commandEnvelope(
            code: 'post_reply_succeed',
            tid: '10001',
            pid: '20002',
          ),
        ]);
        final adapter = _factory(
          network,
        ).createThreadReply(const _FixtureFormhashProvider());

        final result = await adapter.command.execute(
          const ThreadReplySubmission(
            target: ThreadReplyTarget.thread(fid: '30', tid: '10001'),
            message: 'Fixture reply',
            useSignature: true,
          ),
        );

        expect(result, isA<DataCommandApplied<ThreadReplyReceipt>>());
        expect(
          network.requests.single.body,
          containsPair('formhash', 'fixture-formhash'),
        );
        expect(
          network.requests.single.body,
          containsPair('replysubmit', 'yes'),
        );
      },
    );

    test('post reply preserves hidden fields and isolates the quote body', () async {
      final network = _QueueNetwork(<Object?>[
        _replyForm,
        _commandEnvelope(
          code: 'post_reply_succeed',
          tid: '10001',
          pid: '20002',
        ),
      ]);
      final adapter = _factory(
        network,
      ).createThreadReply(const _FixtureFormhashProvider());
      final target = const ThreadReplyTarget.post(
        fid: '30',
        tid: '10001',
        pid: '20001',
      );
      final preparation = (await adapter.preparation.load(
        ThreadReplyPreparationRequest(
          target: target,
          formUri: Uri.parse(
            'https://example.test/forum.php?mod=post&action=reply&fid=30&tid=10001&repquote=20001&extra=&page=231&mobile=2',
          ),
          referer: Uri.parse(
            'https://example.test/forum.php?mod=viewthread&tid=10001&page=231&mobile=2',
          ),
        ),
      )).dataOrNull!;

      expect(network.requests.first.uri.queryParameters['mobile'], isNull);
      expect(network.requests.first.uri.queryParameters['extra'], '');
      expect(network.requests.first.uri.queryParameters['page'], '231');
      expect(network.requests.first.headers['User-Agent'], 'fixture-desktop');
      final preparationReferer = Uri.parse(
        network.requests.first.headers['Referer']!,
      );
      expect(preparationReferer.queryParameters['mobile'], isNull);
      expect(preparationReferer.queryParameters['page'], '231');

      final result = await adapter.command.execute(
        ThreadReplySubmission(
          target: target,
          preparation: preparation,
          message: 'Fixture post reply',
          useSignature: false,
          attachmentIds: const <String>['60001'],
        ),
      );

      expect(preparation.quotePreview, 'Fixture quote body');
      expect(result, isA<DataCommandApplied<ThreadReplyReceipt>>());
      final form = network.requests.last.body!;
      expect(form, containsPair('reppid', '20001'));
      expect(form, containsPair('noticeauthor', 'fixture-notice'));
      expect(form, containsPair('noticeauthormsg', 'Fixture quote body'));
      expect(
        form,
        containsPair(
          'noticetrimstr',
          '[quote][size=2][url=forum.php?mod=redirect&goto=findpost&pid=20001&ptid=10001]Fixture author[/url][/size]\nFixture quote body[/quote]',
        ),
      );
      expect(form, containsPair('attachnew[60001][description]', ''));
    });

    test('post reply rejects a mobile form with a truncated quote', () async {
      final network = _QueueNetwork(<Object?>[_mobileReplyForm]);
      final adapter = _factory(
        network,
      ).createThreadReply(const _FixtureFormhashProvider());

      final result = await adapter.preparation.load(
        ThreadReplyPreparationRequest(
          target: const ThreadReplyTarget.post(
            fid: '30',
            tid: '10001',
            pid: '20001',
          ),
          formUri: Uri.parse(
            'https://example.test/forum.php?mod=post&action=reply&fid=30&tid=10001&repquote=20001&mobile=2',
          ),
        ),
      );

      expect(network.requests.single.uri.queryParameters['mobile'], isNull);
      expect(network.requests.single.headers['User-Agent'], 'fixture-desktop');
      expect(
        result,
        isA<DataReadFailure<ThreadReplyPreparation, ThreadReplyCapabilities>>(),
      );
      expect(
        result.failureOrNull?.code,
        'thread_reply_preparation_parse_failed',
      );
    });

    test('success code without positive pid remains outcome unknown', () async {
      final network = _QueueNetwork(<Object?>[
        _commandEnvelope(code: 'post_reply_succeed', tid: '10001', pid: ''),
      ]);
      final adapter = _factory(
        network,
      ).createThreadReply(const _FixtureFormhashProvider());

      final result = await adapter.command.execute(
        const ThreadReplySubmission(
          target: ThreadReplyTarget.thread(fid: '30', tid: '10001'),
          message: 'Fixture reply',
          useSignature: true,
        ),
      );

      expect(result, isA<DataCommandOutcomeUnknown<ThreadReplyReceipt>>());
      expect(
        result.failureOrNull!.code,
        'thread_reply_receipt_identity_invalid',
      );
    });

    test(
      'classifies namespaced Discuz rejection codes without guessing',
      () async {
        final cases =
            <(String, DataCommandFailureKind, DataCommandRetryPolicy)>[
              (
                'mobile:post_message_tooshort',
                DataCommandFailureKind.validation,
                DataCommandRetryPolicy.afterInputChange,
              ),
              (
                'mobile:replyperm_login_nopermission//1',
                DataCommandFailureKind.unauthenticated,
                DataCommandRetryPolicy.afterSessionRefresh,
              ),
              (
                'mobile:replyperm_none_nopermission',
                DataCommandFailureKind.permissionDenied,
                DataCommandRetryPolicy.explicitOnly,
              ),
              (
                'mobile:fixture_unrecognized_rejection',
                DataCommandFailureKind.unknown,
                DataCommandRetryPolicy.explicitOnly,
              ),
            ];

        for (final (code, expectedKind, expectedRetry) in cases) {
          final network = _QueueNetwork(<Object?>[
            _commandEnvelope(code: code, tid: '', pid: ''),
          ]);
          final adapter = _factory(
            network,
          ).createThreadReply(const _FixtureFormhashProvider());

          final result = await adapter.command.execute(
            const ThreadReplySubmission(
              target: ThreadReplyTarget.thread(fid: '30', tid: '10001'),
              message: 'Fixture reply',
              useSignature: true,
            ),
          );

          expect(result, isA<DataCommandRejected<ThreadReplyReceipt>>());
          expect(result.failureOrNull!.kind, expectedKind, reason: code);
          expect(
            result.failureOrNull!.retryPolicy,
            expectedRetry,
            reason: code,
          );
          expect(result.failureOrNull!.code, code, reason: code);
          expect(result.failureOrNull!.diagnosticMessage, code, reason: code);
        }
      },
    );
  });
}

final _config = ForumClientConfig(
  siteOrigin: Uri.parse('https://example.test'),
  apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
  userAgent: 'fixture-mobile',
  desktopUserAgent: 'fixture-desktop',
);

ForumClientAdapterFactory _factory(ForumClientNetwork network) =>
    ForumClientAdapterFactory(config: _config, network: network);

ThreadCreationSubmission _ordinarySubmission(
  ThreadCreationPreparation preparation, {
  int minimumReadAccess = 0,
}) => ThreadCreationSubmission(
  preparation: preparation,
  subject: 'Fixture subject',
  message: 'Fixture message',
  typeId: '101',
  useSignature: true,
  notifyAuthor: false,
  disableBbCode: false,
  disableSmileys: false,
  disableUrlParsing: false,
  minimumReadAccess: minimumReadAccess,
);

Map<String, Object?> _commandEnvelope({
  required String code,
  required String tid,
  required String pid,
}) => <String, Object?>{
  'Version': '4',
  'Variables': <String, Object?>{'tid': tid, 'pid': pid},
  'Message': <String, Object?>{
    'messageval': code,
    'messagestr': 'private server text',
  },
};

final _preparationEnvelope = <String, Object?>{
  'Version': '4',
  'Variables': <String, Object?>{
    'formhash': 'fixture-formhash',
    'forum': <String, Object?>{
      'fid': '30',
      'name': 'Fixture forum',
      'maxsubject': '80',
      'maxpostsize': '10000',
    },
    'threadtypes': <String, Object?>{
      'required': '1',
      'types': <String, Object?>{'101': 'Type A', '102': 'Type B'},
    },
    'threadsorts': <String, Object?>{
      'required': '0',
      'types': <String, Object?>{},
    },
  },
};

const _replyForm = '''
<html><body id="nv_forum" class="pg_post">
<form id="postform" action="forum.php?mod=post&amp;action=reply&amp;fid=30&amp;tid=10001&amp;replysubmit=yes">
  <input name="formhash" value="fixture-prepared-formhash">
  <input name="fid" value="30">
  <input name="tid" value="10001">
  <input name="reppid" value="20001">
  <input name="reppost" value="20001">
  <input name="noticeauthor" value="fixture-notice">
  <input name="noticetrimstr" value="[quote][size=2][url=forum.php?mod=redirect&amp;goto=findpost&amp;pid=20001&amp;ptid=10001]Fixture author[/url][/size]
Fixture quote body[/quote]">
  <input name="noticeauthormsg" value="Fixture quote body">
  <div class="post_from">
    RE: Fixture subject
    <div class="quote"><blockquote>
      fixture-user posted at fixture-time<br>Fixture quote body
    </blockquote></div>
  </div>
</form>
</body></html>
''';

const _mobileReplyForm = '''
<html><body id="forum" class="pg_post">
<form id="postform" action="forum.php?mod=post&amp;action=reply&amp;fid=30&amp;tid=10001&amp;replysubmit=yes&amp;mobile=2">
  <input name="formhash" value="fixture-prepared-formhash">
  <input name="fid" value="30">
  <input name="tid" value="10001">
  <input name="reppid" value="20001">
  <input name="reppost" value="20001">
  <input name="noticeauthor" value="fixture-notice">
  <input name="noticetrimstr" value="[quote]Fixture author\nFixture quote body[/quote]">
  <input name="noticeauthormsg" value="Fixture quote body">
</form>
</body></html>
''';

final class _QueueNetwork implements ForumClientNetwork {
  _QueueNetwork(this.responses);

  final List<Object?> responses;
  final List<ForumRequest> requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const <String, List<String>>{},
        body: responses.removeAt(0),
      ),
    );
  }
}

final class _FixtureFormhashProvider implements ForumFormhashProvider {
  const _FixtureFormhashProvider();

  @override
  Future<ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
    ForumRequestCancellation? cancellation,
  }) async => const ForumFormhashSuccess('fixture-formhash');
}
