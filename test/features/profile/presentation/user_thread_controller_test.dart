import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_controller.dart';

import '../test_support/thread_directory_fixture.dart';

void main() {
  test(
    'URL page and actor survive paging, refresh and retained tab changes',
    () async {
      final repository = ThreadDirectoryFixture();
      final controller = UserThreadController(
        repository: repository,
        viewerUserId: '101',
        args: const UserThreadPageArgs(
          userId: '202',
          initialType: UserThreadDirectoryType.replies,
          initialPage: 3,
        ),
      );
      addTearDown(controller.dispose);
      var pending = controller.setActive(true);
      _expectQuery(
        repository.requests.last,
        UserThreadDirectoryType.replies,
        3,
      );
      repository.succeed(0, hasMore: true);
      await pending;
      pending = controller.loadMore();
      _expectQuery(
        repository.requests.last,
        UserThreadDirectoryType.replies,
        4,
      );
      repository.succeed(
        1,
        items: [
          threadSummary('200', replies: ['601']),
        ],
      );
      await pending;
      expect(controller.value.data!.items, hasLength(2));
      pending = controller.refresh();
      _expectQuery(
        repository.requests.last,
        UserThreadDirectoryType.replies,
        1,
      );
      repository.succeed(2);
      await pending;
      pending = controller.selectType(UserThreadDirectoryType.threads);
      _expectQuery(
        repository.requests.last,
        UserThreadDirectoryType.threads,
        1,
      );
      repository.succeed(3);
      await pending;
      await controller.selectType(UserThreadDirectoryType.replies);
      expect(repository.requests, hasLength(4));
      expect(controller.value.query.page, 1);
      expect(controller.value.data!.items.single.replyPreviews, hasLength(2));
    },
  );

  test(
    'initial URL page survives cancellation and retry; explicit refresh resets it',
    () async {
      final repository = ThreadDirectoryFixture();
      final controller = UserThreadController(
        repository: repository,
        viewerUserId: '101',
        args: const UserThreadPageArgs(userId: '202', initialPage: 3),
      );
      addTearDown(controller.dispose);
      final cancelled = controller.setActive(true);
      await controller.setActive(false);
      expect(repository.requests.first.cancellation!.isCancelled, isTrue);
      var pending = controller.setActive(true);
      _expectQuery(
        repository.requests.last,
        UserThreadDirectoryType.threads,
        3,
      );
      repository.succeed(0, items: [threadSummary('stale')]);
      await cancelled;
      expect(controller.value.data, isNull);
      repository.fail(1, DataReadFailureKind.network);
      await pending;
      pending = controller.retry();
      _expectQuery(
        repository.requests.last,
        UserThreadDirectoryType.threads,
        3,
      );
      repository.fail(2, DataReadFailureKind.network);
      await pending;
      pending = controller.refresh();
      _expectQuery(
        repository.requests.last,
        UserThreadDirectoryType.threads,
        1,
      );
      repository.fail(3, DataReadFailureKind.network);
      await pending;
      pending = controller.retry();
      _expectQuery(
        repository.requests.last,
        UserThreadDirectoryType.threads,
        1,
      );
      repository.succeed(4);
      await pending;
      expect(controller.value.query.page, 1);
    },
  );

  test(
    'a target user does not bypass the verified viewer login requirement',
    () async {
      final repository = ThreadDirectoryFixture();
      final controller = UserThreadController(
        repository: repository,
        viewerUserId: null,
        args: const UserThreadPageArgs(userId: '202'),
      );
      addTearDown(controller.dispose);
      await controller.setActive(true);
      expect(repository.requests, isEmpty);
      expect(controller.value.failure!.kind, DataReadFailureKind.unauthorized);
    },
  );

  test(
    'business rejection of the next page clears both tabs and retries that page without merging',
    () async {
      final repository = ThreadDirectoryFixture();
      final controller = UserThreadController(
        repository: repository,
        viewerUserId: '101',
        args: const UserThreadPageArgs(userId: '202'),
      );
      addTearDown(controller.dispose);
      var pending = controller.setActive(true);
      repository.succeed(0);
      await pending;
      pending = controller.selectType(UserThreadDirectoryType.replies);
      repository.succeed(1, hasMore: true);
      await pending;
      pending = controller.loadMore();
      repository.fail(2, DataReadFailureKind.business);
      await pending;
      expect(controller.value.data, isNull);
      expect(
        controller.stateForType(UserThreadDirectoryType.threads).data,
        isNull,
      );
      expect(controller.value.query.page, 2);
      pending = controller.retry();
      _expectQuery(
        repository.requests.last,
        UserThreadDirectoryType.replies,
        2,
      );
      repository.succeed(
        3,
        items: [
          threadSummary('fresh', replies: ['601']),
        ],
      );
      await pending;
      expect(controller.value.data!.items.single.threadId, 'fresh');
      pending = controller.selectType(UserThreadDirectoryType.threads);
      _expectQuery(
        repository.requests.last,
        UserThreadDirectoryType.threads,
        1,
      );
      repository.succeed(4);
      await pending;
    },
  );

  test(
    'business rejection of refresh retries page one instead of the preceding URL page',
    () async {
      final repository = ThreadDirectoryFixture();
      final controller = UserThreadController(
        repository: repository,
        viewerUserId: '101',
        args: const UserThreadPageArgs(userId: '202', initialPage: 5),
      );
      addTearDown(controller.dispose);
      var pending = controller.setActive(true);
      repository.succeed(0);
      await pending;
      pending = controller.refresh();
      repository.fail(1, DataReadFailureKind.business);
      await pending;
      expect(controller.value.data, isNull);
      expect(controller.value.query.page, 1);
      pending = controller.retry();
      _expectQuery(
        repository.requests.last,
        UserThreadDirectoryType.threads,
        1,
      );
      repository.succeed(2, items: [threadSummary('fresh')]);
      await pending;
      expect(controller.value.data!.items.single.threadId, 'fresh');
    },
  );
}

void _expectQuery(
  ThreadDirectoryRequest request,
  UserThreadDirectoryType type,
  int page,
) {
  expect(
    request.query,
    UserThreadDirectoryQuery(
      userId: '202',
      viewerUserId: '101',
      type: type,
      page: page,
    ),
  );
}
