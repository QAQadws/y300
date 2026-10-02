import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/domain/private_message_compose_repository.dart';
import 'package:y300/features/messages/presentation/message_friend_directory_controller.dart';

void main() {
  late _ComposeRepository repository;
  late String account;
  late MessageFriendDirectoryController controller;
  late bool disposed;

  setUp(() {
    repository = _ComposeRepository();
    account = '10';
    disposed = false;
    controller = MessageFriendDirectoryController(
      accountId: '10',
      currentAccountId: () => account,
      repository: repository,
    );
    addTearDown(() {
      if (!disposed) controller.dispose();
    });
  });

  testWidgets('search waits 300 ms and drops an obsolete response', (
    tester,
  ) async {
    final initial = controller.initialize();
    expect(repository.reads.single.query.page, 1);
    controller.setSearchQuery(' Ali ');
    expect(repository.reads.single.query.cancellation!.isCancelled, isTrue);
    repository.reads.first.result.complete(_page(['old']));
    await initial;
    expect(controller.value.items, isEmpty);
    await tester.pump(const Duration(milliseconds: 299));
    expect(repository.reads, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(repository.reads, hasLength(2));
    expect(repository.reads.last.query.username, 'Ali');
    repository.reads.last.result.complete(_page(['Alice']));
    await tester.pump();
    expect(controller.value.items.single.username, 'Alice');
    expect(controller.value.query, 'Ali');
  });

  test(
    'paging is single-flight and a failed page can be retried explicitly',
    () async {
      final initial = controller.initialize();
      repository.reads.single.result.complete(
        _page([for (var i = 1; i <= 20; i++) 'friend$i'], count: 41),
      );
      await initial;
      expect(controller.value.hasMore, isTrue);
      final more = controller.loadMore();
      final joined = controller.loadMore();
      expect(identical(more, joined), isTrue);
      expect(repository.reads.last.query.page, 2);
      repository.reads.last.result.complete(
        const DataReadFailure(
          kind: DataReadFailureKind.network,
          code: 'offline',
          diagnosticMessage: 'offline',
        ),
      );
      await more;
      expect(controller.value.items, hasLength(20));
      expect(
        controller.value.failedOperation,
        MessageFriendDirectoryOperation.more,
      );
      expect(repository.reads, hasLength(2));
      final retry = controller.loadMore();
      expect(repository.reads.last.query.page, 2);
      repository.reads.last.result.complete(
        _page(['friend20', 'friend21'], page: 2, count: 41, startId: 119),
      );
      await retry;
      expect(controller.value.items, hasLength(21));
      expect(controller.value.items.last.username, 'friend21');
    },
  );

  test(
    'nullable owner is accepted but a proved different owner is rejected',
    () async {
      final initial = controller.initialize();
      repository.reads.single.result.complete(_page(['Alice']));
      await initial;
      expect(controller.value.items.single.username, 'Alice');

      final refresh = controller.refresh();
      repository.reads.last.result.complete(_page(['Other'], owner: '11'));
      await refresh;
      expect(controller.value.items, isEmpty);
      expect(controller.value.failure?.kind, DataReadFailureKind.unauthorized);
    },
  );

  test('account change or disposal cancels and ignores late pages', () async {
    final pending = controller.initialize();
    account = '11';
    expect(repository.reads.single.query.cancellation!.isCancelled, isFalse);
    controller.dispose();
    disposed = true;
    repository.reads.single.result.complete(_page(['old account']));
    await pending;
    expect(repository.reads.single.query.cancellation!.isCancelled, isTrue);
  });
}

FriendDirectoryRead _page(
  List<String> names, {
  int page = 1,
  int count = 20,
  String? owner,
  int? startId,
}) => DataReadSuccess(
  data: ForumFriendDirectoryPage(
    items: [
      for (var i = 0; i < names.length; i++)
        ForumFriendDirectoryItem(
          userId: '${(startId ?? page * 100) + i}',
          username: names[i],
        ),
    ],
    page: page,
    perPage: 20,
    count: count,
    currentUserId: owner,
  ),
  capabilities: ForumFriendDirectoryReadCapabilities(
    values: DataCapabilitySet.supported(ForumFriendDirectoryCapability.values),
  ),
  metadata: const DataReadMetadata.network(),
);

class _ComposeRepository implements PrivateMessageComposeRepository {
  final reads = <_FriendRead>[];

  @override
  Future<FriendDirectoryRead> loadFriends(ForumFriendDirectoryQuery query) {
    final read = _FriendRead(query);
    reads.add(read);
    return read.result.future;
  }

  @override
  Future<DataCommandResult<ForumPrivateMessageBatchReceipt>> sendBatch(
    ForumPrivateMessageBatchSubmission submission,
  ) => throw UnimplementedError();
}

class _FriendRead {
  _FriendRead(this.query);

  final ForumFriendDirectoryQuery query;
  final result = Completer<FriendDirectoryRead>();
}
