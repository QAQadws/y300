import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://example.test'),
    userAgent: 'mobile-test',
    desktopUserAgent: 'desktop-test',
  );

  group('DiscuzThreadPostRatingAdapter', () {
    test(
      'prepares every server score dimension without fallback data',
      () async {
        final network = _QueueNetwork(<Object?>[_ratingForm]);
        final adapter = ForumClientAdapterFactory(
          config: config,
          network: network,
        ).createThreadPostRatingInteraction();

        final result = await adapter.preparation.load(
          const ThreadPostRatingPreparationRequest(tid: '10001', pid: '20001'),
        );

        final success =
            result
                as DataReadSuccess<
                  ThreadPostRatingPreparation,
                  ThreadPostRatingCapabilities
                >;
        expect(success.data.dimensions, hasLength(2));
        expect(success.data.dimensions.first.id, 'score1');
        expect(success.data.dimensions.first.minimum, 0);
        expect(success.data.dimensions.first.maximum, 5);
        expect(success.data.dimensions.first.initialScore, 0);
        expect(success.data.dimensions.last.id, 'score2');
        expect(success.data.dimensions.last.initialScore, 0);
        expect(success.data.reasonSuggestions, <String>['fixture reason']);
        expect(success.metadata.origin, DataReadOrigin.network);
        expect(network.requests.single.uri.queryParameters['action'], 'rate');
      },
    );

    test(
      'accepts only stable JSON success code and returns safe receipt',
      () async {
        final network = _QueueNetwork(<Object?>[
          _ratingForm,
          '{"Message":{"messageval":"thread_rate_succeed",'
              '"messagestr":"server text must stay private"}}',
        ]);
        final adapter = ForumClientAdapterFactory(
          config: config,
          network: network,
        ).createThreadPostRatingInteraction();
        final preparation = (await adapter.preparation.load(
          const ThreadPostRatingPreparationRequest(tid: '10001', pid: '20001'),
        )).dataOrNull!;

        final result = await adapter.command.execute(
          ThreadPostRatingSubmission(
            preparation: preparation,
            scores: const <String, int>{'score1': 5, 'score2': 1},
            reason: 'fixture reason',
            notifyAuthor: true,
          ),
        );

        expect(result, isA<DataCommandApplied<ThreadPostRatingReceipt>>());
        expect(result.receiptOrNull!.tid, '10001');
        expect(result.receiptOrNull!.pid, '20001');
        expect(network.requests.last.body, containsPair('score1', '5'));
        expect(network.requests.last.body, containsPair('score2', '1'));
        expect(result.toString(), isNot(contains('server text')));
      },
    );

    test('does not treat visible success text as command proof', () async {
      final network = _QueueNetwork(<Object?>[
        _ratingForm,
        '<html><body><p>评分成功</p></body></html>',
      ]);
      final adapter = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createThreadPostRatingInteraction();
      final preparation = (await adapter.preparation.load(
        const ThreadPostRatingPreparationRequest(tid: '10001', pid: '20001'),
      )).dataOrNull!;

      final result = await adapter.command.execute(
        ThreadPostRatingSubmission(
          preparation: preparation,
          scores: const <String, int>{'score1': 5, 'score2': 1},
          reason: 'fixture reason',
          notifyAuthor: false,
        ),
      );

      expect(result, isA<DataCommandOutcomeUnknown<ThreadPostRatingReceipt>>());
      expect(result.failureOrNull!.code, 'thread_interaction_callback_missing');
    });

    test('empty submitted response remains outcome unknown', () async {
      final network = _QueueNetwork(<Object?>[_ratingForm, '']);
      final adapter = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createThreadPostRatingInteraction();
      final preparation = (await adapter.preparation.load(
        const ThreadPostRatingPreparationRequest(tid: '10001', pid: '20001'),
      )).dataOrNull!;

      final result = await adapter.command.execute(
        ThreadPostRatingSubmission(
          preparation: preparation,
          scores: const <String, int>{'score1': 5, 'score2': 1},
          reason: 'fixture reason',
          notifyAuthor: false,
        ),
      );

      expect(result, isA<DataCommandOutcomeUnknown<ThreadPostRatingReceipt>>());
      expect(result.failureOrNull!.code, 'thread_interaction_response_empty');
    });
  });

  group('DiscuzThreadPostCommentAdapter', () {
    test(
      'prepares and submits plain text through explicit AJAX proof',
      () async {
        final network = _QueueNetwork(<Object?>[
          _commentForm,
          "<root><![CDATA[<script>succeedhandle_comment('', '', "
              "{'tid':'10001','pid':'20001'});</script>]]></root>",
        ]);
        final adapter = ForumClientAdapterFactory(
          config: config,
          network: network,
        ).createThreadPostCommentInteraction();
        final prepared = await adapter.preparation.load(
          const ThreadPostCommentPreparationRequest(tid: '10001', pid: '20001'),
        );
        final preparation = prepared.dataOrNull!;

        final result = await adapter.command.execute(
          ThreadPostCommentSubmission(
            preparation: preparation,
            message: 'fixture comment',
          ),
        );

        expect(preparation.maxLength, 200);
        expect(result, isA<DataCommandApplied<ThreadPostCommentReceipt>>());
        expect(network.requests.last.uri.queryParameters['inajax'], '1');
        expect(
          network.requests.last.body,
          containsPair('message', 'fixture comment'),
        );
      },
    );

    test('identity mismatch after submit remains outcome unknown', () async {
      final network = _QueueNetwork(<Object?>[
        _commentForm,
        "<root><![CDATA[<script>succeedhandle_comment('', '', "
            "{'tid':'10001','pid':'99999'});</script>]]></root>",
      ]);
      final adapter = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createThreadPostCommentInteraction();
      final preparation = (await adapter.preparation.load(
        const ThreadPostCommentPreparationRequest(tid: '10001', pid: '20001'),
      )).dataOrNull!;

      final result = await adapter.command.execute(
        ThreadPostCommentSubmission(
          preparation: preparation,
          message: 'fixture comment',
        ),
      );

      expect(
        result,
        isA<DataCommandOutcomeUnknown<ThreadPostCommentReceipt>>(),
      );
      expect(
        result.failureOrNull!.code,
        'thread_interaction_identity_mismatch',
      );
    });

    test(
      'explicit error callback is rejected without exposing payload',
      () async {
        final network = _QueueNetwork(<Object?>[
          _commentForm,
          "<root><![CDATA[<script>errorhandle_comment('private server text', "
              "{});</script>]]></root>",
        ]);
        final adapter = ForumClientAdapterFactory(
          config: config,
          network: network,
        ).createThreadPostCommentInteraction();
        final preparation = (await adapter.preparation.load(
          const ThreadPostCommentPreparationRequest(tid: '10001', pid: '20001'),
        )).dataOrNull!;

        final result = await adapter.command.execute(
          ThreadPostCommentSubmission(
            preparation: preparation,
            message: 'fixture comment',
          ),
        );

        expect(result, isA<DataCommandRejected<ThreadPostCommentReceipt>>());
        expect(
          result.failureOrNull!.diagnosticMessage,
          isNot(contains('private')),
        );
      },
    );

    test(
      'unsupported security fields fail closed during preparation',
      () async {
        final network = _QueueNetwork(<Object?>[
          _commentForm.replaceFirst(
            '<textarea name="message"></textarea>',
            '<input name="seccodeverify" value="">'
                '<textarea name="message"></textarea>',
          ),
        ]);
        final adapter = ForumClientAdapterFactory(
          config: config,
          network: network,
        ).createThreadPostCommentInteraction();

        final result = await adapter.preparation.load(
          const ThreadPostCommentPreparationRequest(tid: '10001', pid: '20001'),
        );

        expect(
          result,
          isA<
            DataReadFailure<
              ThreadPostCommentPreparation,
              ThreadPostCommentCapabilities
            >
          >(),
        );
        expect(result.failureOrNull!.kind, DataReadFailureKind.parse);
        expect(network.requests, hasLength(1));
      },
    );
  });
}

final class _QueueNetwork implements ForumClientNetwork {
  _QueueNetwork(this.responses);

  final List<Object?> responses;
  final List<ForumRequest> requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    final body = responses.removeAt(0);
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

const _ratingForm = '''
<root><![CDATA[
<form id="rateform" method="post"
 action="forum.php?mod=misc&amp;action=rate&amp;ratesubmit=yes&amp;infloat=yes">
 <input name="formhash" value="fixture-formhash">
 <input name="tid" value="10001">
 <input name="pid" value="20001">
 <input name="referer" value="https://example.test/forum.php?mod=viewthread&amp;tid=10001">
 <input name="handlekey" value="rate">
 <table>
  <tr><td>Fixture points</td><td><input name="score1" value="0"></td><td>0 ~ 5</td><td>10</td></tr>
  <tr><td>Fixture bonus</td><td><input name="score2" value="0"></td><td>-1 ~ 1</td><td>2</td></tr>
 </table>
 <ul id="reasonselect"><li>fixture reason</li></ul>
 <input type="checkbox" name="sendreasonpm" checked>
</form>
]]></root>
''';

const _commentForm = '''
<root><![CDATA[
<form id="commentform" method="post"
 action="forum.php?mod=post&amp;action=reply&amp;comment=yes&amp;tid=10001&amp;pid=20001&amp;page=1&amp;commentsubmit=yes&amp;infloat=yes">
 <input name="formhash" value="fixture-formhash">
 <input name="handlekey" value="comment">
 <textarea name="message"></textarea>
 <strong id="checklen">200</strong>
</form>
]]></root>
''';
