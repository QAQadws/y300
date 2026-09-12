import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/domain/message_refresh_bus.dart';
import 'package:y300/features/messages/domain/message_repository.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';

void main() {
  late _Repository repository;
  late ProviderContainer container;
  setUp(() {
    repository = _Repository();
    container = ProviderContainer.test(
      overrides: [
        messageRepositoryProvider.overrideWithValue(repository),
        messageAccountIdProvider.overrideWithValue('10'),
      ],
    );
  });

  test(
    'closing one of two consumers does not deactivate the surviving owner',
    () async {
      final controller = container
          .listen(privateMessageFeedProvider(null), (_, _) {})
          .read();
      final firstOwner = Object();
      final secondOwner = Object();
      controller.setActive(true, owner: firstOwner);
      controller.setActive(true, owner: secondOwner);
      repository.messageReads.last.result.complete(_messages(['1']));
      await controller.refresh();
      controller.setActive(false, owner: firstOwner);
      controller.invalidate();
      expect(repository.messageReads, hasLength(2));
      repository.messageReads.last.result.complete(_messages(['2']));
      await controller.refresh();
      controller.setActive(false, owner: secondOwner);
      controller.invalidate();
      expect(repository.messageReads, hasLength(2));
    },
  );

  test('feeds fail independently and never preload the other tab', () async {
    final pm = container
        .listen(privateMessageFeedProvider(null), (_, _) {})
        .read();
    final notifications = container
        .listen(notificationFeedProvider, (_, _) {})
        .read();
    final first = pm.refresh();
    expect(repository.notificationReads, isEmpty);
    repository.messageReads.last.result.complete(
      const DataReadFailure(
        kind: DataReadFailureKind.timeout,
        code: 'fixture',
        diagnosticMessage: 'fixture',
      ),
    );
    await first;
    final second = notifications.refresh();
    repository.notificationReads.last.complete(_notices());
    await second;
    expect(pm.value.failure, isNotNull);
    expect(notifications.value.data, isNotNull);
  });

  test(
    'conversation history prepends, deduplicates and keeps its reply anchor',
    () async {
      final controller = container
          .listen(
            privateMessageFeedProvider(
              const ForumConversationTarget.group('91'),
            ),
            (_, _) {},
          )
          .read();
      final latest = controller.refresh();
      expect(repository.messageReads.last.query.page, 0);
      repository.messageReads.last.result.complete(
        _messages(['3', '4'], page: 2, anchor: '3'),
      );
      await latest;
      final older = controller.loadMore();
      expect(repository.messageReads.last.query.page, 1);
      repository.messageReads.last.result.complete(
        _messages(['1', '2', '3'], page: 1, anchor: '1'),
      );
      await older;
      expect(controller.value.data!.items.map((item) => item.messageId), [
        '1',
        '2',
        '3',
        '4',
      ]);
      expect(controller.value.data!.replyMessageId, '3');
      expect(controller.hasMore, isFalse);
      final refresh = controller.refresh();
      repository.messageReads.last.result.complete(
        _messages(['4', '5'], page: 3, anchor: '4'),
      );
      await refresh;
      expect(controller.value.data!.items.map((item) => item.messageId), [
        '1',
        '2',
        '3',
        '4',
        '5',
      ]);
      expect(controller.value.data!.page, 1);
      expect(controller.value.data!.replyMessageId, '4');
    },
  );

  test(
    'refresh events are isolated by account, kind and conversation',
    () async {
      const target = ForumConversationTarget.direct('20');
      final controller = container
          .listen(privateMessageFeedProvider(target), (_, _) {})
          .read();
      controller.setActive(true);
      final initial = controller.refresh();
      repository.messageReads.last.result.complete(_messages(['1']));
      await initial;
      final bus = container.read(messageRefreshBusProvider);
      bus.publish(
        const MessageRefreshEvent(
          accountId: '11',
          kind: MessageRefreshKind.messages,
          target: target,
        ),
      );
      bus.publish(
        const MessageRefreshEvent(
          accountId: '10',
          kind: MessageRefreshKind.notifications,
          target: target,
        ),
      );
      bus.publish(
        const MessageRefreshEvent(
          accountId: '10',
          kind: MessageRefreshKind.messages,
          target: ForumConversationTarget.direct('30'),
        ),
      );
      expect(repository.messageReads, hasLength(1));
      bus.publish(
        const MessageRefreshEvent(
          accountId: '10',
          kind: MessageRefreshKind.messages,
          target: target,
        ),
      );
      expect(repository.messageReads, hasLength(2));
      final refresh = controller.refresh();
      repository.messageReads.last.result.complete(_messages(['1', '2']));
      await refresh;
    },
  );

  test(
    'account changes dispose old reads and do not retain the old mailbox',
    () async {
      final subscription = container.listen(
        privateMessageFeedProvider(null),
        (_, _) {},
      );
      final previous = subscription.read();
      final pending = previous.refresh();
      final old = repository.messageReads.last;
      container.updateOverrides([
        messageRepositoryProvider.overrideWithValue(repository),
        messageAccountIdProvider.overrideWithValue('11'),
      ]);
      final current = subscription.read();
      expect(current, isNot(same(previous)));
      expect(old.query.cancellation!.isCancelled, isTrue);
      old.result.complete(_messages(['1']));
      await pending;
      expect(current.value.data, isNull);
      final fresh = current.refresh();
      repository.messageReads.last.result.complete(
        _messages(['2'], owner: '11'),
      );
      await fresh;
      expect(current.value.data!.items.single.messageId, '2');
    },
  );

  test('new message page growth cannot skip the next older messages', () async {
    const target = ForumConversationTarget.direct('20');
    final controller = container
        .listen(privateMessageFeedProvider(target), (_, _) {})
        .read();
    final first = controller.refresh();
    repository.messageReads.last.result.complete(
      _messages(['5', '6'], page: 3, count: 6),
    );
    await first;
    final refresh = controller.refresh();
    repository.messageReads.last.result.complete(
      _messages(['6', '7'], page: 4, count: 7),
    );
    await refresh;
    final more = controller.loadMore();
    expect(repository.messageReads.last.query.page, 3);
    repository.messageReads.last.result.complete(
      _messages(['4', '5'], page: 3, count: 7),
    );
    await more;
    expect(controller.value.data!.items.map((item) => item.messageId), [
      '4',
      '5',
      '6',
      '7',
    ]);
  });

  test(
    'conversation directory deduplicates changed last-message IDs',
    () async {
      final controller = container
          .listen(privateMessageFeedProvider(null), (_, _) {})
          .read();
      final first = controller.refresh();
      repository.messageReads.last.result.complete(_messages(['1']));
      await first;
      final more = controller.loadMore();
      repository.messageReads.last.result.complete(_messages(['2'], page: 2));
      await more;
      expect(controller.value.data!.items.single.messageId, '2');
    },
  );

  test(
    'new messages arriving during history loading rebase before merging',
    () async {
      const target = ForumConversationTarget.direct('20');
      final controller = container
          .listen(privateMessageFeedProvider(target), (_, _) {})
          .read();
      final first = controller.refresh();
      repository.messageReads.last.result.complete(
        _messages(['5', '6'], page: 3, count: 6),
      );
      await first;
      final more = controller.loadMore();
      expect(repository.messageReads.last.query.page, 2);
      repository.messageReads.last.result.complete(
        _messages(['2', '3'], page: 2, count: 7),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.messageReads.last.query.page, 3);
      expect(controller.value.data!.items.map((item) => item.messageId), [
        '5',
        '6',
      ]);
      repository.messageReads.last.result.complete(
        _messages(['4', '5'], page: 3, count: 7),
      );
      await more;
      expect(controller.value.data!.items.map((item) => item.messageId), [
        '4',
        '5',
        '6',
      ]);
    },
  );

  test('response from a different account is not shown', () async {
    final controller = container
        .listen(privateMessageFeedProvider(null), (_, _) {})
        .read();
    final pending = controller.refresh();
    repository.messageReads.last.result.complete(_messages(['1'], owner: '11'));
    await pending;
    expect(controller.value.data, isNull);
    expect(controller.value.failure?.kind, DataReadFailureKind.unauthorized);
  });

  test('signed-out feeds do not access private endpoints', () async {
    container.updateOverrides([
      messageRepositoryProvider.overrideWithValue(repository),
      messageAccountIdProvider.overrideWithValue(null),
    ]);
    final controller = container
        .listen(privateMessageFeedProvider(null), (_, _) {})
        .read();
    await controller.refresh();
    expect(controller.value.failure?.kind, DataReadFailureKind.unauthorized);
    expect(repository.messageReads, isEmpty);
  });
}

PrivateMessageRead _messages(
  List<String> ids, {
  int page = 1,
  String anchor = '',
  String owner = '10',
  int count = 6,
}) => DataReadSuccess(
  data: ForumPrivateMessagePage(
    items: [
      for (final id in ids)
        ForumPrivateMessageItem(
          messageId: id,
          conversationId: '91',
          isNew: false,
          subject: '',
          fromUserId: '20',
          fromUserName: 'friend',
          toUserId: '10',
          toUserName: '',
          message: 'fixture',
          sentAt: null,
          rawDateline: '',
        ),
    ],
    count: count,
    page: page,
    perPage: 2,
    currentUserId: owner,
    replyMessageId: anchor,
  ),
  capabilities: ForumPrivateMessageReadCapabilities(
    values: DataCapabilitySet.supported(ForumPrivateMessageCapability.values),
  ),
  metadata: const DataReadMetadata.network(),
);
NotificationRead _notices() => DataReadSuccess(
  data: const ForumNotificationPage(items: [], count: 0, page: 1, perPage: 30),
  capabilities: ForumNotificationReadCapabilities(
    values: DataCapabilitySet.supported(ForumNotificationCapability.values),
  ),
  metadata: const DataReadMetadata.network(),
);

final class _MessageRead {
  _MessageRead(this.query);
  final ForumPrivateMessageQuery query;
  final result = Completer<PrivateMessageRead>();
}

final class _Repository implements MessageRepository {
  final messageReads = <_MessageRead>[];
  final notificationReads = <Completer<NotificationRead>>[];
  @override
  Future<PrivateMessageRead> loadMessages(ForumPrivateMessageQuery query) {
    final read = _MessageRead(query);
    messageReads.add(read);
    return read.result.future;
  }

  @override
  Future<NotificationRead> loadNotifications(ForumNotificationQuery query) {
    final read = Completer<NotificationRead>();
    notificationReads.add(read);
    return read.future;
  }

  @override
  Future<DataCommandResult<ForumPrivateMessageReceipt>> send(
    ForumPrivateMessageSubmission submission,
  ) async => const DataCommandUnsupported();
  @override
  Future<DataCommandResult<ForumNotificationIgnoreReceipt>> ignore(
    ForumNotificationIgnoreSubmission submission,
  ) async => const DataCommandUnsupported();
}
