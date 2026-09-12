import 'dart:async';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  late _Network network;
  late _Formhash formhash;
  late ForumNotificationIgnoreCommand command;
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://forum.example.test'),
    userAgent: 'mobile',
    desktopUserAgent: 'desktop',
  );
  setUp(() {
    network = _Network();
    formhash = _Formhash();
    command = ForumClientAdapterFactory(
      config: config,
      network: network,
    ).createNotificationIgnoreCommand(formhash);
  });

  for (final scope in ForumNotificationIgnoreScope.values) {
    test(
      'installs ${scope.name} filter and confirms matching server tuple',
      () async {
        final author = scope == ForumNotificationIgnoreScope.author
            ? '20'
            : '0';
        network.body = _success(author: author);
        final result = await command.execute(_submission(scope: scope));
        expect(
          result,
          isA<DataCommandApplied<ForumNotificationIgnoreReceipt>>(),
        );
        expect(result.receiptOrNull!.authorId, author);
        expect(result.receiptOrNull!.type, 'post');
        expect(result.receiptOrNull!.notificationId, '41');
        final request = network.requests.single;
        expect(request.method, ForumRequestMethod.post);
        expect(request.followRedirects, isFalse);
        expect(request.headers['User-Agent'], 'desktop');
        expect(request.uri.queryParameters, {
          'mod': 'spacecp',
          'ac': 'common',
          'op': 'ignore',
          'type': 'post',
          'id': '41',
          'inajax': '1',
          'handlekey': 'y300_notice_ignore',
        });
        expect(request.body, {
          'formhash': 'fixture-hash',
          'ignoresubmit': 'true',
          'authorid': author,
          'referer': _referer,
          'handlekey': 'y300_notice_ignore',
        });
        expect(formhash.calls, 1);
      },
    );
  }

  test(
    'does not mistake arbitrary success text or unrelated callbacks for proof',
    () async {
      final invalid = [
        'do_success',
        '<p>succeedhandle_y300_notice_ignore()</p>',
        _success(author: '21'),
        _success(type: 'friend'),
        _success(id: '42'),
        _success(handle: 'other'),
        _success(forward: 'https://other.example.test'),
        _success()
            .replaceAll('<script>', '<div>')
            .replaceAll('</script>', '</div>'),
        _success() + _success(),
        '<script>var text = "succeedhandle_y300_notice_ignore(abc)";</script>',
        '<script>succeedhandle_y300_notice_ignore(\'$_referer\', \'done\');</script>',
      ];
      for (final body in invalid) {
        network.body = body;
        network.requests.clear();
        final result = await command.execute(_submission());
        expect(
          result,
          isA<DataCommandOutcomeUnknown<ForumNotificationIgnoreReceipt>>(),
          reason: body,
        );
        expect(network.requests, hasLength(1));
      }
    },
  );

  test('escaped human-readable messages cannot fabricate a callback', () async {
    network.body = _success().replaceAll(
      "'done'",
      r"'can\'t show private text'",
    );
    expect(
      await command.execute(_submission()),
      isA<DataCommandApplied<ForumNotificationIgnoreReceipt>>(),
    );
  });

  test('explicit error callback is a safe rejection', () async {
    network.body =
        '<root><![CDATA[<script>if(true){errorhandle_y300_notice_ignore(\'private payload\', {});}</script>]]></root>';
    final result = await command.execute(_submission());
    expect(result, isA<DataCommandRejected<ForumNotificationIgnoreReceipt>>());
    expect(
      result.failureOrNull!.diagnosticMessage,
      'notification_ignore_rejected',
    );
  });

  test(
    'transport failure and redirects do not prove the filter was saved',
    () async {
      network.failure = true;
      expect(
        await command.execute(_submission()),
        isA<DataCommandOutcomeUnknown<ForumNotificationIgnoreReceipt>>(),
      );
      network.failure = false;
      network.status = 302;
      expect(
        await command.execute(_submission()),
        isA<DataCommandOutcomeUnknown<ForumNotificationIgnoreReceipt>>(),
      );
      network.status = 200;
      network.responseUri = Uri.parse('https://other.example.test/home.php');
      expect(
        await command.execute(_submission()),
        isA<DataCommandOutcomeUnknown<ForumNotificationIgnoreReceipt>>(),
      );
      network.responseUri = null;
      network.throws = true;
      expect(
        await command.execute(_submission()),
        isA<DataCommandOutcomeUnknown<ForumNotificationIgnoreReceipt>>(),
      );
    },
  );

  test('invalid identities cannot change the filter target', () async {
    for (final submission in [
      _submission(id: '0'),
      _submission(type: ''),
      _submission(type: 'post&uid=0'),
      _submission(author: '0'),
      _submission(author: '-1'),
    ]) {
      expect(
        await command.execute(submission),
        isA<DataCommandNotSent<ForumNotificationIgnoreReceipt>>(),
      );
    }
    expect(network.requests, isEmpty);
    expect(formhash.calls, 0);
  });

  test('system notifications can only use the all-authors scope', () async {
    network.body = _success(author: '0');
    final result = await command.execute(
      _submission(author: '0', scope: ForumNotificationIgnoreScope.allAuthors),
    );
    expect(result, isA<DataCommandApplied<ForumNotificationIgnoreReceipt>>());
  });

  test('cancellation while preparing does not submit', () async {
    final cancellation = ForumRequestCancellation();
    formhash.pending = Completer<void>();
    final result = command.execute(_submission(cancellation: cancellation));
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    formhash.pending!.complete();
    expect(
      await result,
      isA<DataCommandNotSent<ForumNotificationIgnoreReceipt>>(),
    );
    expect(network.requests, isEmpty);
  });

  test('formhash failure does not submit', () async {
    formhash.result = const ForumFormhashError(
      ForumTransportFailure(
        kind: ForumTransportFailureKind.unauthorized,
        code: 'login_required',
      ),
    );
    final result = await command.execute(_submission());
    expect(result, isA<DataCommandNotSent<ForumNotificationIgnoreReceipt>>());
    expect(result.failureOrNull!.kind, DataCommandFailureKind.unauthenticated);
    formhash.result = const ForumFormhashSuccess('');
    expect(
      await command.execute(_submission()),
      isA<DataCommandNotSent<ForumNotificationIgnoreReceipt>>(),
    );
    expect(network.requests, isEmpty);
  });

  test('facade and source overlays preserve command installation', () async {
    final missing = YamiboForumClient(config: config, network: network);
    expect(
      await missing.ignoreNotifications(_submission()),
      isA<DataCommandUnsupported<ForumNotificationIgnoreReceipt>>(),
    );
    final installed = YamiboForumClientBuilder(
      config: config,
      network: network,
      formhashProvider: formhash,
    ).buildStandardClient();
    expect(
      await installed.ignoreNotifications(_submission()),
      isA<DataCommandApplied<ForumNotificationIgnoreReceipt>>(),
    );
    final plan = ForumClientSourcePlan(notificationIgnoreCommand: command);
    expect(
      plan.overlay(const ForumClientSourcePlan()).notificationIgnoreCommand,
      same(command),
    );
    expect(
      const ForumClientSourcePlan().overlay(plan).notificationIgnoreCommand,
      same(command),
    );
  });
}

const _referer = 'https://forum.example.test/home.php?mod=space&do=notice';
ForumNotificationIgnoreSubmission _submission({
  String id = '41',
  String type = 'post',
  String author = '20',
  ForumNotificationIgnoreScope scope = ForumNotificationIgnoreScope.author,
  ForumRequestCancellation? cancellation,
}) => ForumNotificationIgnoreSubmission(
  notificationId: id,
  type: type,
  authorId: author,
  scope: scope,
  cancellation: cancellation,
);

// Mirrors function_message.php's desktop AJAX callback including the exact
// id/type/uid values returned by spacecp_common.php after privacy_update().
String _success({
  String id = '41',
  String type = 'post',
  String author = '20',
  String handle = 'y300_notice_ignore',
  String forward = _referer,
}) =>
    '<root><![CDATA[<script>if(typeof succeedhandle_$handle==\'function\'){succeedhandle_$handle(\'$forward\', \'done\', {\'id\':\'$id\',\'type\':\'$type\',\'uid\':\'$author\'});}</script>]]></root>';

final class _Network implements ForumClientNetwork {
  final requests = <ForumRequest>[];
  Object? body = _success();
  bool failure = false;
  bool throws = false;
  int status = 200;
  Uri? responseUri;
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    if (throws) throw StateError('fixture');
    if (failure) {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.timeout,
          code: 'fixture_timeout',
        ),
      );
    }
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

final class _Formhash implements ForumFormhashProvider {
  int calls = 0;
  Completer<void>? pending;
  ForumFormhashResult result = const ForumFormhashSuccess('fixture-hash');
  @override
  Future<ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
    ForumRequestCancellation? cancellation,
  }) async {
    calls++;
    await pending?.future;
    return result;
  }
}
