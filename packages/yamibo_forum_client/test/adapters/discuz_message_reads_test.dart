import 'dart:async';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  late _Network network;
  late ForumClientAdapterFactory factory;

  setUp(() {
    network = _Network();
    factory = ForumClientAdapterFactory(
      config: ForumClientConfig(
        siteOrigin: Uri.parse('https://forum.example.test'),
        apiOrigin: Uri.parse('https://forum.example.test/api/mobile/index.php'),
        userAgent: 'fixture',
      ),
      network: network,
    );
  });

  test(
    'directory preserves group routing and exact timestamps via v1',
    () async {
      network.variables = _page([_direct, _group], count: 32, page: 2);
      final result = await factory.createPrivateMessages().load(
        const ForumPrivateMessageQuery(page: 2),
      );
      final query = network.requests.single.uri.queryParameters;
      expect(query, containsPair('module', 'mypm'));
      expect(query, containsPair('version', '1'));
      expect(query, containsPair('page', '2'));
      expect(query, containsPair('filter', 'privatepm'));
      expect(query.containsKey('subop'), isFalse);
      final page = result.dataOrNull!;
      expect(page.hasNext, isTrue);
      expect(page.hasPrevious, isTrue);
      expect(page.currentUserId, '10');
      expect(
        page.items.first.target,
        const ForumConversationTarget.direct('20'),
      );
      expect(page.items.last.target, const ForumConversationTarget.group('92'));
      expect(page.items.last.isGroupConversation, isTrue);
      expect(page.items.last.participantCount, 3);
      expect(page.items.last.fromUserName, '群成员');
      expect(page.items.first.sentAt, DateTime.utc(2026, 1, 1));
    },
  );

  test(
    'direct conversation opens latest page and preserves server order',
    () async {
      network.variables = {
        ..._page(
          [
            _direct,
            {..._direct, 'pmid': '82', 'msgfromid': '10'},
          ],
          count: 32,
          page: 3,
        ),
        'pmid': '81',
      };
      final result = await factory.createPrivateMessages().load(
        const ForumPrivateMessageQuery.conversation(
          target: ForumConversationTarget.direct('20'),
        ),
      );
      final query = network.requests.single.uri.queryParameters;
      expect(query, containsPair('subop', 'view'));
      expect(query, containsPair('touid', '20'));
      expect(query.containsKey('page'), isFalse);
      expect(query.containsKey('plid'), isFalse);
      expect(query.containsKey('daterange'), isFalse);
      final page = result.dataOrNull!;
      expect(page.page, 3);
      expect(page.replyMessageId, '81');
      expect(page.items.map((item) => item.messageId), ['81', '82']);
      expect(page.items.first.message, contains('<br>'));
      expect(page.hasNext, isFalse);
      expect(page.hasPrevious, isTrue);
    },
  );

  test(
    'group history uses the group namespace and explicit older page',
    () async {
      network.variables = _page([_group], count: 35, page: 1);
      final result = await factory.createPrivateMessages().load(
        const ForumPrivateMessageQuery.conversation(
          target: ForumConversationTarget.group('92'),
          page: 1,
        ),
      );
      final query = network.requests.single.uri.queryParameters;
      expect(query, containsPair('plid', '92'));
      expect(query, containsPair('type', '1'));
      expect(query, containsPair('page', '1'));
      expect(query.containsKey('touid'), isFalse);
      expect(result.dataOrNull!.hasPrevious, isFalse);
      expect(result.dataOrNull!.hasNext, isTrue);
    },
  );

  test(
    'a new conversation normalizes Discuz page zero without a fake row',
    () async {
      network.variables = _page([], count: 0, page: 0);
      final result = await factory.createPrivateMessages().load(
        const ForumPrivateMessageQuery.conversation(
          target: ForumConversationTarget.direct('20'),
        ),
      );
      expect(result.dataOrNull!.page, 1);
      expect(result.dataOrNull!.items, isEmpty);
      expect(result.dataOrNull!.hasNext, isFalse);
      expect(result.dataOrNull!.hasPrevious, isFalse);
    },
  );

  test(
    'notifications support pagination and retain actionable markup',
    () async {
      network.variables = _page([_notice], count: 70, page: 2);
      final result = await factory.createNotifications().load(
        const ForumNotificationQuery(page: 2),
      );
      expect(
        network.requests.single.uri.queryParameters,
        containsPair('version', '3'),
      );
      expect(
        network.requests.single.uri.queryParameters,
        containsPair('page', '2'),
      );
      final item = result.dataOrNull!.items.single;
      expect(item.isNew, isTrue);
      expect(item.type, 'post');
      expect(item.authorId, '20');
      expect(item.duplicateCount, 3);
      expect(item.noteMarkup, contains('pid=600'));
      expect(result.dataOrNull!.count, 70);
    },
  );

  test('keyed PHP row objects are read in their supplied order', () async {
    network.variables = {
      ..._page([]),
      'list': {
        '900': _notice,
        '100': {..._notice, 'id': '42'},
      },
    };
    final result = await factory.createNotifications().load(
      const ForumNotificationQuery(),
    );
    expect(result.dataOrNull!.items.map((item) => item.id), ['41', '42']);
  });

  for (final count in [null, -1, 'invalid', '0']) {
    test(
      'missing or invalid duplicate count does not break the notice: $count',
      () async {
        network.variables = _page([
          {..._notice, 'from_num': count},
        ]);
        final result = await factory.createNotifications().load(
          const ForumNotificationQuery(),
        );
        expect(result.dataOrNull!.items.single.duplicateCount, 0);
      },
    );
  }

  for (final query in [
    const ForumPrivateMessageQuery(page: 0),
    const ForumPrivateMessageQuery.conversation(
      target: ForumConversationTarget.direct('0'),
    ),
    const ForumPrivateMessageQuery.conversation(
      target: ForumConversationTarget.group('2&uid=3'),
    ),
    const ForumPrivateMessageQuery.conversation(
      target: ForumConversationTarget.direct('20'),
      page: -1,
    ),
  ]) {
    test(
      'invalid message query is rejected before transport: ${query.target?.id}/${query.page}',
      () async {
        final result = await factory.createPrivateMessages().load(query);
        expect(
          result,
          isA<
            DataReadFailure<
              ForumPrivateMessagePage,
              ForumPrivateMessageReadCapabilities
            >
          >(),
        );
        expect(network.requests, isEmpty);
      },
    );
  }

  test('invalid notification page does not call transport', () async {
    final result = await factory.createNotifications().load(
      const ForumNotificationQuery(page: 0),
    );
    expect(
      result,
      isA<
        DataReadFailure<
          ForumNotificationPage,
          ForumNotificationReadCapabilities
        >
      >(),
    );
    expect(network.requests, isEmpty);
  });

  for (final malformed in <Object?>[
    null,
    'html error',
    [null],
    [<String, Object?>{}],
    {'bad': _direct},
  ]) {
    test(
      'malformed list is a failure, not an empty mailbox: $malformed',
      () async {
        network.variables = {..._page([]), 'list': malformed};
        final result = await factory.createPrivateMessages().load(
          const ForumPrivateMessageQuery(),
        );
        expect((result as DataReadFailure).kind, DataReadFailureKind.parse);
      },
    );
  }

  test('duplicate messages and mismatched pages fail closed', () async {
    network.variables = _page([_direct, _direct]);
    final duplicates = await factory.createPrivateMessages().load(
      const ForumPrivateMessageQuery(),
    );
    expect((duplicates as DataReadFailure).kind, DataReadFailureKind.parse);
    network.variables = _page([_direct], page: 2);
    final mismatched = await factory.createPrivateMessages().load(
      const ForumPrivateMessageQuery(),
    );
    expect((mismatched as DataReadFailure).kind, DataReadFailureKind.parse);
  });

  for (final notifications in [false, true]) {
    test(
      'cancellation rejects late ${notifications ? "notification" : "message"} responses',
      () async {
        final cancellation = ForumRequestCancellation();
        network.pending = Completer<void>();
        final result = notifications
            ? factory.createNotifications().load(
                ForumNotificationQuery(cancellation: cancellation),
              )
            : factory.createPrivateMessages().load(
                ForumPrivateMessageQuery(cancellation: cancellation),
              );
        await Future<void>.delayed(Duration.zero);
        expect(network.requests.single.cancellation, same(cancellation));
        cancellation.cancel();
        network.pending!.complete();
        expect(
          ((await result) as DataReadFailure).kind,
          DataReadFailureKind.cancelled,
        );
        network.requests.clear();
        final cancelled = notifications
            ? await factory.createNotifications().load(
                ForumNotificationQuery(cancellation: cancellation),
              )
            : await factory.createPrivateMessages().load(
                ForumPrivateMessageQuery(cancellation: cancellation),
              );
        expect(
          (cancelled as DataReadFailure).kind,
          DataReadFailureKind.cancelled,
        );
        expect(network.requests, isEmpty);
      },
    );
  }

  test('successive reads do not reuse cached private data', () async {
    final repository = factory.createPrivateMessages();
    network.variables = _page([_direct]);
    await repository.load(const ForumPrivateMessageQuery());
    network.variables = _page([], count: 0);
    final result = await repository.load(const ForumPrivateMessageQuery());
    expect(network.requests, hasLength(2));
    expect(result.dataOrNull!.items, isEmpty);
  });

  test(
    'expired sessions are classified without exposing server text',
    () async {
      network.errorCode = 'login_before_enter_home//1';
      final result = await factory.createPrivateMessages().load(
        const ForumPrivateMessageQuery(),
      );
      final failure =
          result
              as DataReadFailure<
                ForumPrivateMessagePage,
                ForumPrivateMessageReadCapabilities
              >;
      expect(failure.kind, DataReadFailureKind.unauthorized);
      expect(failure.diagnosticMessage, 'message_login_required');
    },
  );
}

// Self-contained projections of api/1/mypm.php and api/3/mynotelist.php.
const _direct = <String, Object?>{
  'pmid': '81',
  'plid': '91',
  'pmtype': '1',
  'isnew': '1',
  'msgfromid': '20',
  'msgfrom': '朋友',
  'touid': '20',
  'tousername': '朋友',
  'message': '第一行<br>第二行',
  'dateline': '1767225600',
  'members': '2',
};
const _group = <String, Object?>{
  'pmid': '82',
  'plid': '92',
  'pmtype': '2',
  'isnew': '0',
  'touid': '0',
  'lastauthorid': '30',
  'lastauthor': '群成员',
  'members': '3',
  'subject': '讨论',
  'message': '新消息',
  'dateline': '1767225700',
};
const _notice = <String, Object?>{
  'id': '41',
  'type': 'post',
  'new': '1',
  'authorid': '20',
  'author': '朋友',
  'from_num': '3',
  'note':
      '<a href="forum.php?mod=redirect&goto=findpost&ptid=500&pid=600">回复</a>',
  'dateline': '1767225600',
};

Map<String, Object?> _page(List<Object?> rows, {int count = 2, int page = 1}) =>
    {
      'list': rows,
      'count': '$count',
      'page': '$page',
      'perpage': '15',
      'member_uid': '10',
    };

final class _Network implements ForumClientNetwork {
  final requests = <ForumRequest>[];
  Map<String, Object?> variables = _page([]);
  Completer<void>? pending;
  String? errorCode;

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    await pending?.future;
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: {
          'Version': request.uri.queryParameters['version'],
          'Variables': variables,
          if (errorCode != null)
            'Message': {
              'messageval': errorCode,
              'messagestr': 'private server payload',
            },
        },
      ),
    );
  }
}
