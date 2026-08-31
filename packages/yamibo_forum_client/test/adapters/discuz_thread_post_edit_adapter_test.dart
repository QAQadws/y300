import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://example.test'),
    apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
    userAgent: 'mobile-html-test',
    desktopUserAgent: 'desktop-html-test',
    apiUserAgent: 'mobile-api-test',
  );

  ThreadPostEditTarget target({
    bool mobile = true,
    bool firstPost = true,
  }) => ThreadPostEditTarget(
    formUri: Uri.parse(
      'https://example.test/forum.php?mod=post&action=edit&fid=30&tid=10001&pid=20001&page=1${mobile ? '&mobile=2' : ''}',
    ),
    fid: '30',
    tid: '10001',
    pid: '20001',
    page: 1,
    kind: firstPost
        ? ThreadPostEditTargetKind.firstPost
        : ThreadPostEditTargetKind.reply,
  );

  test(
    'mobile and desktop edit forms use matching request identities',
    () async {
      for (final mobile in <bool>[true, false]) {
        final network = _QueueNetwork(<Object?>[_editForm(mobile: mobile)]);
        final adapter = ForumClientAdapterFactory(
          config: config,
          network: network,
        ).createThreadPostEdit();

        final result = await adapter.preparation.load(
          ThreadPostEditPreparationRequest(target: target(mobile: mobile)),
        );

        expect(
          result,
          isA<
            DataReadSuccess<
              ThreadPostEditPreparation,
              ThreadPostEditCapabilities
            >
          >(),
        );
        final preparation = result.dataOrNull!;
        expect(preparation.subject, 'fixture subject');
        expect(preparation.message, 'fixture message');
        expect(preparation.useSignature, isTrue);
        expect(preparation.existingImages.single.aid, '30001');
        expect(
          network.requests.single.headers['User-Agent'],
          mobile ? 'mobile-html-test' : 'desktop-html-test',
        );
      }
    },
  );

  test(
    'submits ordered multipart fields and preserves ordinary options',
    () async {
      final network = _QueueNetwork(<Object?>[
        _editForm(),
        "<root><![CDATA[<script>succeedhandle_postform('forum.php?mod=redirect&goto=findpost&ptid=10001&pid=20001', '', {'fid':'30','tid':'10001','pid':'20001'});</script>]]></root>",
      ]);
      final adapter = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createThreadPostEdit();
      final preparation = (await adapter.preparation.load(
        ThreadPostEditPreparationRequest(target: target()),
      )).dataOrNull!;

      final result = await adapter.command.execute(
        ThreadPostEditSubmission(
          preparation: preparation,
          subject: 'updated subject',
          message: 'updated [attach]40001[/attach]',
          useSignature: false,
          newImageAttachmentIds: const <String>['40001'],
        ),
      );

      expect(result, isA<DataCommandApplied<ThreadPostEditReceipt>>());
      expect(
        result.receiptOrNull!.confirmation,
        ThreadPostEditConfirmation.serverCallback,
      );
      final request = network.requests.last;
      expect(request.uri.queryParameters['inajax'], '1');
      expect(request.uri.queryParameters['handlekey'], 'postform');
      expect(request.headers['User-Agent'], 'mobile-html-test');
      final fields = (request.body as ForumMultipartFields).entries;
      final pairs = fields.map((entry) => (entry.key, entry.value));
      expect(pairs, contains(('readperm', '20')));
      expect(pairs, contains(('subject', 'updated subject')));
      expect(pairs, contains(('message', 'updated [attach]40001[/attach]')));
      expect(pairs, contains(('attachnew[40001][description]', '')));
      expect(fields.where((entry) => entry.key == 'usesig'), isEmpty);
    },
  );

  test('explicit Discuz callback errors retain stable failure codes', () async {
    final network = _QueueNetwork(<Object?>[
      _editForm(),
      "<root><![CDATA[<script>errorhandle_postform('submit_invalid', {});</script>]]></root>",
    ]);
    final adapter = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createThreadPostEdit();
    final preparation = (await adapter.preparation.load(
      ThreadPostEditPreparationRequest(target: target()),
    )).dataOrNull!;

    final result = await adapter.command.execute(
      ThreadPostEditSubmission(
        preparation: preparation,
        subject: 'fixture subject',
        message: 'updated message',
        useSignature: true,
      ),
    );

    expect(result, isA<DataCommandRejected<ThreadPostEditReceipt>>());
    expect(result.failureOrNull!.kind, DataCommandFailureKind.staleFormhash);
    expect(result.failureOrNull!.code, 'submit_invalid');
  });

  test(
    'an ambiguous submit is confirmed only by a changed matching readback',
    () async {
      final network = _QueueNetwork(<Object?>[
        _editForm(),
        const ForumTransportFailure(
          kind: ForumTransportFailureKind.timeout,
          code: 'timeout',
        ),
        _editForm(subject: 'updated subject', message: 'updated message'),
      ]);
      final adapter = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createThreadPostEdit();
      final preparation = (await adapter.preparation.load(
        ThreadPostEditPreparationRequest(target: target()),
      )).dataOrNull!;

      final result = await adapter.command.execute(
        ThreadPostEditSubmission(
          preparation: preparation,
          subject: 'updated subject',
          message: 'updated message',
          useSignature: true,
        ),
      );

      expect(result, isA<DataCommandApplied<ThreadPostEditReceipt>>());
      expect(
        result.receiptOrNull!.confirmation,
        ThreadPostEditConfirmation.readback,
      );
      expect(
        network.requests.where(
          (request) => request.method == ForumRequestMethod.post,
        ),
        hasLength(1),
      );
    },
  );

  test('special and structurally unknown forms fail closed', () async {
    final network = _QueueNetwork(<Object?>[
      _editForm(extra: '<input name="special" value="1">'),
    ]);
    final adapter = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createThreadPostEdit();

    final result = await adapter.preparation.load(
      ThreadPostEditPreparationRequest(target: target()),
    );

    expect(
      result,
      isA<
        DataReadFailure<ThreadPostEditPreparation, ThreadPostEditCapabilities>
      >(),
    );
    expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
    expect(result.failureOrNull!.code, 'post_edit_special_thread_unsupported');
  });

  test(
    'rejects a submit action whose display mode differs from entry',
    () async {
      final network = _QueueNetwork(<Object?>[_editForm(mobile: false)]);
      final adapter = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createThreadPostEdit();

      final result = await adapter.preparation.load(
        ThreadPostEditPreparationRequest(target: target()),
      );

      expect(
        result,
        isA<
          DataReadFailure<ThreadPostEditPreparation, ThreadPostEditCapabilities>
        >(),
      );
      expect(result.failureOrNull!.code, 'post_edit_submit_uri_invalid');
    },
  );

  test('standard builder installs one edit adapter for both slots', () {
    final client = YamiboForumClientBuilder(
      config: config,
      network: _QueueNetwork(const <Object?>[]),
    ).buildStandardClient();

    expect(client.threadPostEditPreparation, isNotNull);
    expect(
      client.threadPostEditCommand,
      same(client.threadPostEditPreparation),
    );
  });
}

String _editForm({
  String subject = 'fixture subject',
  String message = 'fixture message',
  String extra = '',
  bool mobile = true,
}) =>
    '''
<!doctype html><html><body>
<form id="postform" method="post" enctype="multipart/form-data"
 action="forum.php?mod=post&amp;action=edit&amp;editsubmit=yes&amp;fid=30&amp;tid=10001&amp;pid=20001&amp;page=1${mobile ? '&amp;mobile=2' : ''}">
 <input name="formhash" value="fixture-formhash">
 <input name="posttime" value="100000">
 <input name="fid" value="30">
 <input name="tid" value="10001">
 <input name="pid" value="20001">
 <input name="page" value="1">
 <input name="subject" value="$subject">
 <textarea id="needmessage" name="message">$message</textarea>
 <select name="readperm"><option value="0">none</option><option value="20" selected>20</option></select>
 <input type="checkbox" name="usesig" value="1" checked>
 <input type="hidden" name="editsubmit" value="yes">
 $extra
</form>
<ul id="imglist"><li><span aid="30001" up="1"></span>
 <img src="forum.php?mod=image&amp;aid=30001" alt="fixture.png">
 <input name="attachnew[30001][description]" value="fixture">
</li></ul>
</body></html>
''';

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
