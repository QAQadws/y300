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

  const callback =
      "<script>succeedhandle_postform('forum.php?mod=redirect&goto=findpost&ptid=10001&pid=20001', '', {'fid':'30','tid':'10001','pid':'20001'});</script>";
  Map<String, Object?> permission(
    int value, {
    String tid = '10001',
    String fid = '30',
  }) => {
    'Version': '4',
    'Variables': {
      'fid': fid,
      'thread': {'tid': tid, 'readperm': '$value'},
    },
  };
  String withAccess(String control) => _editForm().replaceFirst(
    RegExp(r'<select name="readperm">.*?</select>'),
    control,
  );

  test(
    'unselected edit permissions use identity-checked v4 readback and preserve obsolete values',
    () async {
      final network = _QueueNetwork([
        _editForm().replaceFirst(' selected', ''),
        permission(37),
        callback,
      ]);
      final adapter = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createThreadPostEdit();
      final prepared = (await adapter.preparation.load(
        ThreadPostEditPreparationRequest(target: target()),
      )).dataOrNull!;
      expect(prepared.readAccess.currentValue, 37);
      expect(prepared.readAccess.allows(37), isFalse);
      expect(
        network.requests[1].uri.queryParameters,
        containsPair('module', 'viewthread'),
      );
      expect(
        network.requests[1].uri.queryParameters,
        containsPair('version', '4'),
      );
      final result = await adapter.command.execute(
        ThreadPostEditSubmission(
          preparation: prepared,
          subject: prepared.subject,
          message: 'updated',
          useSignature: true,
        ),
      );
      expect(result, isA<DataCommandApplied<ThreadPostEditReceipt>>());
      expect(
        (network.requests.last.body as ForumMultipartFields).entries
            .where((e) => e.key == 'readperm')
            .single
            .value,
        '37',
      );
    },
  );

  test(
    'unresolved or mismatched permission readback blocks native preparation',
    () async {
      for (final response in [
        permission(20, tid: '999'),
        permission(20, fid: '99'),
        {'Version': '4', 'Variables': <String, Object?>{}},
        const ForumTransportFailure(
          kind: ForumTransportFailureKind.timeout,
          code: 'timeout',
        ),
      ]) {
        final network = _QueueNetwork([
          _editForm().replaceFirst(' selected', ''),
          response,
        ]);
        final adapter = ForumClientAdapterFactory(
          config: config,
          network: network,
        ).createThreadPostEdit();
        final result = await adapter.preparation.load(
          ThreadPostEditPreparationRequest(target: target()),
        );
        expect(result.dataOrNull, isNull);
        expect(network.requests, hasLength(2));
      }
    },
  );

  test(
    'same-valued selections serialize once and permission affects revision',
    () async {
      final same = withAccess(
        '<select name="readperm"><option value="20" selected>A</option><option value="20" selected>B</option></select>',
      );
      final network = _QueueNetwork([
        same,
        callback,
        same.replaceAll('value="20"', 'value="40"'),
      ]);
      final adapter = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createThreadPostEdit();
      final prepared = (await adapter.preparation.load(
        ThreadPostEditPreparationRequest(target: target()),
      )).dataOrNull!;
      await adapter.command.execute(
        ThreadPostEditSubmission(
          preparation: prepared,
          subject: prepared.subject,
          message: 'updated',
          useSignature: true,
        ),
      );
      expect(
        (network.requests[1].body as ForumMultipartFields).entries.where(
          (e) => e.key == 'readperm',
        ),
        hasLength(1),
      );
      final changed = (await adapter.preparation.load(
        ThreadPostEditPreparationRequest(target: target()),
      )).dataOrNull!;
      expect(changed.revision, isNot(prepared.revision));
    },
  );

  test(
    'missing or disabled controls are omitted, without supplementary requests',
    () async {
      for (final control in [
        '',
        '<select name="readperm" disabled><option value="20" selected>A</option></select>',
        '<fieldset disabled><select name="readperm"><option value="20" selected>A</option></select></fieldset>',
      ]) {
        final network = _QueueNetwork([withAccess(control), callback]);
        final adapter = ForumClientAdapterFactory(
          config: config,
          network: network,
        ).createThreadPostEdit();
        final prepared = (await adapter.preparation.load(
          ThreadPostEditPreparationRequest(target: target()),
        )).dataOrNull!;
        expect(prepared.readAccess.canModify, isFalse);
        final rejected = await adapter.command.execute(
          ThreadPostEditSubmission(
            preparation: prepared,
            subject: prepared.subject,
            message: 'updated',
            useSignature: true,
            minimumReadAccess: 0,
          ),
        );
        expect(rejected, isA<DataCommandNotSent<ThreadPostEditReceipt>>());
        await adapter.command.execute(
          ThreadPostEditSubmission(
            preparation: prepared,
            subject: prepared.subject,
            message: 'updated',
            useSignature: true,
          ),
        );
        expect(
          (network.requests.last.body as ForumMultipartFields).entries.where(
            (e) => e.key == 'readperm',
          ),
          isEmpty,
        );
        expect(network.requests, hasLength(2));
      }
    },
  );

  test(
    'clearing permissions reads back zero; adjusted and unavailable evidence stays applied',
    () async {
      for (final actual in <int?>[0, 20, null]) {
        final network = _QueueNetwork([
          _editForm(),
          callback,
          actual == null
              ? const ForumTransportFailure(
                  kind: ForumTransportFailureKind.timeout,
                  code: 'timeout',
                )
              : permission(actual),
        ]);
        final adapter = ForumClientAdapterFactory(
          config: config,
          network: network,
        ).createThreadPostEdit();
        final prepared = (await adapter.preparation.load(
          ThreadPostEditPreparationRequest(target: target()),
        )).dataOrNull!;
        final result = await adapter.command.execute(
          ThreadPostEditSubmission(
            preparation: prepared,
            subject: prepared.subject,
            message: prepared.message,
            useSignature: true,
            minimumReadAccess: 0,
          ),
        );
        expect(result, isA<DataCommandApplied<ThreadPostEditReceipt>>());
        expect(
          result.receiptOrNull!.readAccess!.kind,
          actual == null
              ? ThreadReadAccessEvidenceKind.unverified
              : actual == 0
              ? ThreadReadAccessEvidenceKind.confirmed
              : ThreadReadAccessEvidenceKind.serverAdjusted,
        );
        expect(
          (network.requests[1].body as ForumMultipartFields).entries
              .where((e) => e.key == 'readperm')
              .single
              .value,
          '0',
        );
        expect(
          network.requests.where((r) => r.method == ForumRequestMethod.post),
          hasLength(1),
        );
      }
    },
  );

  test(
    'unknown outcome with a mismatched permission is never confirmed or resent',
    () async {
      final network = _QueueNetwork([
        _editForm(),
        const ForumTransportFailure(
          kind: ForumTransportFailureKind.timeout,
          code: 'timeout',
        ),
        _editForm(message: 'updated'),
      ]);
      final adapter = ForumClientAdapterFactory(
        config: config,
        network: network,
      ).createThreadPostEdit();
      final prepared = (await adapter.preparation.load(
        ThreadPostEditPreparationRequest(target: target()),
      )).dataOrNull!;
      final result = await adapter.command.execute(
        ThreadPostEditSubmission(
          preparation: prepared,
          subject: prepared.subject,
          message: 'updated',
          useSignature: true,
          minimumReadAccess: 0,
        ),
      );
      expect(result, isA<DataCommandOutcomeUnknown<ThreadPostEditReceipt>>());
      expect(
        network.requests.where((r) => r.method == ForumRequestMethod.post),
        hasLength(1),
      );
    },
  );

  test('replies omit topic permission even if a template exposes it', () async {
    final network = _QueueNetwork([_editForm(), callback]);
    final adapter = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createThreadPostEdit();
    final prepared = (await adapter.preparation.load(
      ThreadPostEditPreparationRequest(target: target(firstPost: false)),
    )).dataOrNull!;
    expect(prepared.readAccess.canModify, isFalse);
    await adapter.command.execute(
      ThreadPostEditSubmission(
        preparation: prepared,
        subject: prepared.subject,
        message: 'updated',
        useSignature: true,
      ),
    );
    expect(
      (network.requests.last.body as ForumMultipartFields).entries.where(
        (e) => e.key == 'readperm',
      ),
      isEmpty,
    );
  });

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
