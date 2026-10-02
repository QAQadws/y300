import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/thread_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/threads/my_thread_controller.dart';

import '../test_support/thread_directory_fixture.dart';

void main() {
  test(
    'tabs load lazily, cancel stale reads and retain their own data',
    () async {
      final repository = ThreadDirectoryFixture();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      expect(repository.requests, isEmpty);
      final first = controller.setActive(true);
      expect(controller.setActive(true), same(first));
      final second = controller.selectType(UserThreadDirectoryType.replies);
      expect(repository.requests.first.cancellation!.isCancelled, isTrue);
      repository.succeed(0, items: [threadSummary('old')]);
      await first;
      expect(controller.value.data, isNull);
      repository.succeed(1);
      await second;
      expect(controller.value.data!.items.single.replyPreviews, hasLength(2));
      final third = controller.selectType(UserThreadDirectoryType.threads);
      repository.succeed(2);
      await third;
      await controller.selectType(UserThreadDirectoryType.replies);
      expect(repository.requests, hasLength(3));
      expect(controller.value.data!.items.single.replyPreviews, hasLength(2));
    },
  );

  test(
    'pagination merges topic groups without losing separate reply PIDs',
    () async {
      final repository = ThreadDirectoryFixture();
      final controller = _controller(
        repository,
        UserThreadDirectoryType.replies,
      );
      addTearDown(controller.dispose);
      var pending = controller.setActive(true);
      repository.succeed(
        0,
        items: [
          threadSummary('100', replies: ['501']),
        ],
        hasMore: true,
      );
      await pending;
      pending = controller.loadMore();
      expect(repository.requests.last.query.page, 2);
      expect(controller.loadMore(), same(pending));
      repository.succeed(
        1,
        items: [
          threadSummary('100', replies: ['501', '502']),
          threadSummary('200', replies: ['601']),
        ],
      );
      await pending;
      final items = controller.value.data!.items;
      expect(items.map((item) => item.threadId), ['100', '200']);
      expect(items.first.replyPreviews.map((reply) => reply.postId), [
        '501',
        '502',
      ]);
      await controller.loadMore();
      expect(repository.requests, hasLength(2));
      pending = controller.refresh();
      repository.succeed(2, items: [threadSummary('300')]);
      await pending;
      expect(controller.value.data!.items.single.threadId, '300');
      expect(controller.value.query.page, 1);
    },
  );

  test('failed pagination retains content and retries the same page', () async {
    final repository = ThreadDirectoryFixture();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    var pending = controller.setActive(true);
    repository.succeed(0, hasMore: true);
    await pending;
    pending = controller.loadMore();
    repository.fail(1, DataReadFailureKind.network);
    await pending;
    expect(controller.value.data!.items, hasLength(1));
    expect(controller.value.query.page, 1);
    expect(controller.value.failedOperation, MyThreadReadOperation.more);
    pending = controller.retry();
    expect(repository.requests.last.query.page, 2);
    repository.succeed(2, items: [threadSummary('200')]);
    await pending;
    expect(controller.value.data!.items, hasLength(2));
    expect(controller.value.failure, isNull);
  });

  test(
    'refresh supersedes more; hidden reads cannot commit late results',
    () async {
      final repository = ThreadDirectoryFixture();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      var pending = controller.setActive(true);
      repository.succeed(0, hasMore: true);
      await pending;
      final more = controller.loadMore();
      pending = controller.refresh();
      expect(repository.requests[1].cancellation!.isCancelled, isTrue);
      repository.succeed(1, items: [threadSummary('stale')]);
      await more;
      repository.succeed(2, items: [threadSummary('fresh')], hasMore: true);
      await pending;
      expect(controller.value.data!.items.single.threadId, 'fresh');
      final hidden = controller.loadMore();
      await controller.setActive(false);
      expect(repository.requests.last.cancellation!.isCancelled, isTrue);
      repository.succeed(3, items: [threadSummary('hidden')]);
      await hidden;
      expect(controller.value.data!.items.single.threadId, 'fresh');
      await controller.refresh();
      expect(repository.requests, hasLength(4));
    },
  );

  test('unauthorized response clears retained personal tabs', () async {
    final repository = ThreadDirectoryFixture();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    var pending = controller.setActive(true);
    repository.succeed(0);
    await pending;
    pending = controller.selectType(UserThreadDirectoryType.replies);
    repository.fail(1, DataReadFailureKind.unauthorized);
    await pending;
    expect(controller.value.data, isNull);
    expect(
      controller.stateForType(UserThreadDirectoryType.threads).data,
      isNull,
    );
  });

  test('guest does not access the directory repository', () async {
    final repository = ThreadDirectoryFixture();
    final controller = MyThreadController(
      repository: repository,
      accountId: null,
      args: const MyThreadPageArgs(),
    );
    addTearDown(controller.dispose);
    await controller.setActive(true);
    expect(repository.requests, isEmpty);
    expect(controller.value.failure!.kind, DataReadFailureKind.unauthorized);
  });

  test(
    'same UID with a new session revision disposes the old read owner',
    () async {
      final repository = ThreadDirectoryFixture();
      final container = ProviderContainer(
        overrides: [
          verifiedProfileOwnerProvider.overrideWithValue((
            uid: '101',
            revision: 0,
          )),
          userThreadDirectoryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        myThreadControllerProvider(const MyThreadPageArgs()),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final old = subscription.read();
      final pending = old.setActive(true);
      container.updateOverrides([
        verifiedProfileOwnerProvider.overrideWithValue((
          uid: '101',
          revision: 1,
        )),
        userThreadDirectoryRepositoryProvider.overrideWithValue(repository),
      ]);
      await container.pump();
      final current = subscription.read();
      expect(current, isNot(same(old)));
      expect(repository.requests.first.cancellation!.isCancelled, isTrue);
      repository.succeed(0);
      await pending;
      expect(current.value.data, isNull);
    },
  );
}

MyThreadController _controller(
  ThreadDirectoryFixture repository, [
  UserThreadDirectoryType type = UserThreadDirectoryType.threads,
]) => MyThreadController(
  repository: repository,
  accountId: '101',
  args: MyThreadPageArgs(initialType: type),
);
