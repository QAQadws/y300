import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/friend_read_providers.dart';
import 'package:y300/features/profile/presentation/friends/my_friends_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

import '../test_support/friend_read_fixture.dart';

const _owner = (uid: '101', revision: 0);

void main() {
  test(
    'hidden lists are lazy and repeated active reads share one flight',
    () async {
      final repository = FriendFeedFixture();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      await controller.setActive(false);
      for (final scope in ForumFriendFeedScope.values) {
        expect(controller.stateForScope(scope).data, isNull);
      }
      expect(repository.requests, isEmpty);

      final pending = controller.setActive(true);
      expect(controller.value.isLoading, isTrue);
      expect(controller.setActive(true), same(pending));
      expect(controller.refresh(), same(pending));
      repository.succeed(0);
      await pending;
      await controller.setActive(false);
      await controller.setActive(true);
      expect(repository.requests, hasLength(1));
    },
  );

  test(
    'scope changes cancel obsolete results and retain completed pages',
    () async {
      final repository = FriendFeedFixture();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      final first = controller.setActive(true);
      final online = controller.selectScope(ForumFriendFeedScope.online);
      expect(repository.requests.first.query.cancellation!.isCancelled, isTrue);
      repository.succeed(1, items: [friendFeedItem('303')]);
      await online;
      repository.succeed(0, items: [friendFeedItem('old')]);
      await first;
      expect(controller.value.query.scope, ForumFriendFeedScope.online);
      expect(controller.value.data!.items.single.userId, '303');

      final friends = controller.selectScope(ForumFriendFeedScope.friends);
      repository.succeed(2, items: [friendFeedItem('202')]);
      await friends;
      await controller.selectScope(ForumFriendFeedScope.online);
      expect(repository.requests, hasLength(3));
      expect(controller.value.data!.items.single.userId, '303');
    },
  );

  test(
    'paging follows server bounds and replaces rather than merges rows',
    () async {
      final repository = FriendFeedFixture();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      var pending = controller.setActive(true);
      repository.succeed(0, totalPages: 4);
      await pending;
      expect(controller.value.currentPage, 1);
      expect(controller.value.lastPage, 4);
      expect(controller.value.canLoadPrevious, isFalse);
      await controller.loadPreviousPage();
      await controller.loadPageNumber(0);
      await controller.loadPageNumber(1);
      await controller.loadPageNumber(5);
      expect(repository.requests, hasLength(1));

      pending = controller.loadPageNumber(4);
      expect(repository.requests.last.query.page, 4);
      expect(controller.value.currentPage, 1);
      expect(controller.value.data!.items.single.userId, '202');
      await controller.loadNextPage();
      final duplicate = controller.loadPageNumber(2);
      expect(repository.requests, hasLength(2));
      // The response's exact page count overrides a stale next-page link.
      repository.succeed(
        1,
        page: 4,
        totalPages: 4,
        hasNext: true,
        items: [friendFeedItem('303')],
      );
      await pending;
      await duplicate;
      expect(controller.value.currentPage, 4);
      expect(controller.value.query.page, 4);
      expect(controller.value.lastPage, 4);
      expect(controller.value.canLoadNext, isFalse);
      expect(controller.value.data!.items.single.userId, '303');

      pending = controller.selectScope(ForumFriendFeedScope.visitors);
      repository.succeed(2, items: [friendFeedItem('404')]);
      await pending;
      await controller.selectScope(ForumFriendFeedScope.friends);
      expect(repository.requests, hasLength(3));
      expect(controller.value.currentPage, 4);
      pending = controller.loadPreviousPage();
      expect(repository.requests.last.query.page, 3);
      repository.succeed(3, items: [friendFeedItem('505')]);
      await pending;
      expect(controller.value.data!.items.single.userId, '505');
    },
  );

  test('network failures retain rows and allow an explicit retry', () async {
    final repository = FriendFeedFixture();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    var pending = controller.setActive(true);
    repository.succeed(0);
    await pending;
    pending = controller.loadNextPage();
    repository.fail(1, DataReadFailureKind.network);
    await pending;
    expect(controller.value.data!.items.single.userId, '202');
    expect(controller.value.currentPage, 1);
    expect(controller.value.failure!.kind, DataReadFailureKind.network);
    pending = controller.loadNextPage();
    expect(repository.requests.last.query.page, 2);
    repository.succeed(2, items: [friendFeedItem('303')]);
    await pending;
    expect(controller.value.failure, isNull);
    expect(controller.value.data!.items.single.userId, '303');
  });

  for (final identityMismatch in [false, true]) {
    test(
      '${identityMismatch ? 'proved owner mismatch' : 'unauthorized response'} clears every retained private list',
      () async {
        final repository = FriendFeedFixture();
        final controller = _controller(repository);
        addTearDown(controller.dispose);
        var pending = controller.setActive(true);
        repository.succeed(0);
        await pending;
        pending = controller.selectScope(ForumFriendFeedScope.online);
        if (identityMismatch) {
          repository.succeed(1, currentUserId: '999');
        } else {
          repository.fail(1, DataReadFailureKind.unauthorized);
        }
        await pending;
        expect(controller.value.data, isNull);
        expect(
          controller.value.failure!.kind,
          DataReadFailureKind.unauthorized,
        );
        for (final scope in ForumFriendFeedScope.values) {
          expect(controller.stateForScope(scope).data, isNull);
        }
      },
    );
  }

  test(
    'hiding the page cancels a read and ignores its late response',
    () async {
      final repository = FriendFeedFixture();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      final pending = controller.setActive(true);
      await controller.setActive(false);
      expect(repository.requests.first.query.cancellation!.isCancelled, isTrue);
      repository.succeed(0);
      await pending;
      expect(controller.value.data, isNull);
      expect(controller.value.isLoading, isFalse);
    },
  );

  test('guests never read or remove account friends', () async {
    final repository = FriendFeedFixture();
    final removal = FriendRemovalFixture();
    final controller = _controller(repository, removal: removal, owner: null);
    addTearDown(controller.dispose);
    await controller.setActive(true);
    await controller.removeFriend('202');
    expect(repository.requests, isEmpty);
    expect(removal.requests, isEmpty);
    expect(controller.value.failure!.kind, DataReadFailureKind.unauthorized);
  });

  for (final nextOwner in <VerifiedProfileOwner?>[
    (uid: '999', revision: 1),
    (uid: '101', revision: 1),
    null,
  ]) {
    test(
      'owner transition to $nextOwner disposes old reads and commands',
      () async {
        final repository = FriendFeedFixture();
        final removal = FriendRemovalFixture();
        final container = ProviderContainer(
          overrides: [
            verifiedProfileOwnerProvider.overrideWithValue(_owner),
            friendFeedRepositoryProvider.overrideWithValue(repository),
            friendRemovalCommandProvider.overrideWithValue(removal),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          myFriendsControllerProvider(const MyFriendsPageArgs()),
          (_, _) {},
        );
        addTearDown(subscription.close);
        final old = subscription.read();
        final pending = old.setActive(true);
        container.updateOverrides([
          verifiedProfileOwnerProvider.overrideWithValue(nextOwner),
          friendFeedRepositoryProvider.overrideWithValue(repository),
          friendRemovalCommandProvider.overrideWithValue(removal),
        ]);
        await container.pump();
        final current = subscription.read();
        expect(current, isNot(same(old)));
        expect(
          repository.requests.first.query.cancellation!.isCancelled,
          isTrue,
        );
        repository.succeed(0);
        await pending;
        expect(current.value.data, isNull);
        await old.removeFriend('202');
        expect(removal.requests, isEmpty);
      },
    );
  }

  test(
    'only an applied removal refreshes lists and duplicate taps send once',
    () async {
      final repository = FriendFeedFixture();
      final removal = FriendRemovalFixture();
      final controller = _controller(repository, removal: removal);
      addTearDown(controller.dispose);
      final load = controller.setActive(true);
      repository.succeed(0);
      await load;
      final pending = controller.removeFriend('202');
      expect(controller.value.isRemoving, isTrue);
      expect(controller.value.removingUserId, '202');
      final duplicate = controller.removeFriend('202');
      expect(removal.requests, hasLength(1));
      removal.applied();
      await Future<void>.delayed(Duration.zero);
      expect(repository.requests, hasLength(2));
      expect(
        repository.requests.last.cachePolicy,
        CacheLoadPolicy.networkFirst,
      );
      repository.succeed(1, items: [], hasNext: false, totalPages: 1);
      final result = await pending;
      await duplicate;
      expect(result, isA<DataCommandApplied<ForumFriendRemovalReceipt>>());
      expect(controller.value.data!.items, isEmpty);
      expect(controller.value.isRemoving, isFalse);
    },
  );

  for (final unknown in [false, true]) {
    test(
      '${unknown ? 'unknown' : 'rejected'} removal keeps rows without automatic refresh or retry',
      () async {
        final repository = FriendFeedFixture();
        final removal = FriendRemovalFixture();
        final controller = _controller(repository, removal: removal);
        addTearDown(controller.dispose);
        final load = controller.setActive(true);
        repository.succeed(0);
        await load;
        final pending = controller.removeFriend('202');
        if (unknown) {
          removal.outcomeUnknown();
        } else {
          removal.rejected();
        }
        await pending;
        expect(repository.requests, hasLength(1));
        expect(removal.requests, hasLength(1));
        expect(controller.value.data!.items.single.userId, '202');
        expect(controller.value.isRemoving, isFalse);
        if (unknown) {
          expect(controller.value.unverifiedRemovalUserIds, contains('202'));
          await controller.removeFriend('202');
          expect(removal.requests, hasLength(1));

          var refresh = controller.refresh();
          repository.fail(1, DataReadFailureKind.network);
          await refresh;
          expect(controller.value.unverifiedRemovalUserIds, contains('202'));
          refresh = controller.refresh();
          repository.succeed(
            2,
            metadata: const DataReadMetadata(
              origin: DataReadOrigin.cachedDocumentFallback,
              freshness: DataReadFreshness.staleOrUnknown,
            ),
          );
          await refresh;
          expect(controller.value.unverifiedRemovalUserIds, contains('202'));
          refresh = controller.refresh();
          repository.succeed(3);
          await refresh;
          expect(
            controller.value.unverifiedRemovalUserIds,
            isNot(contains('202')),
          );
        }
      },
    );
  }

  test(
    'unavailable row removal is refused before calling the command',
    () async {
      final repository = FriendFeedFixture();
      final removal = FriendRemovalFixture();
      final controller = _controller(repository, removal: removal);
      addTearDown(controller.dispose);
      final load = controller.setActive(true);
      repository.succeed(0, items: [friendFeedItem('202', canRemove: false)]);
      await load;
      await controller.removeFriend('202');
      await controller.removeFriend('999');
      expect(removal.requests, isEmpty);
    },
  );

  test('inbound scope and page survive switching tabs and refresh', () async {
    final repository = FriendFeedFixture();
    final controller = _controller(
      repository,
      args: const MyFriendsPageArgs(
        initialScope: ForumFriendFeedScope.footprints,
        initialPage: 3,
      ),
    );
    addTearDown(controller.dispose);
    var pending = controller.setActive(true);
    expect(
      repository.requests.single.query.scope,
      ForumFriendFeedScope.footprints,
    );
    expect(repository.requests.single.query.page, 3);
    repository.succeed(0);
    await pending;
    pending = controller.selectScope(ForumFriendFeedScope.friends);
    repository.succeed(1);
    await pending;
    await controller.selectScope(ForumFriendFeedScope.footprints);
    expect(repository.requests, hasLength(2));
    pending = controller.refresh();
    expect(
      repository.requests.last.query.scope,
      ForumFriendFeedScope.footprints,
    );
    expect(repository.requests.last.query.page, 3);
    repository.succeed(2);
    await pending;
  });

  test(
    'old session removal cannot refresh or lock the current owner',
    () async {
      final repository = FriendFeedFixture();
      final removal = FriendRemovalFixture();
      VerifiedProfileOwner? currentOwner = _owner;
      final controller = MyFriendsController(
        repository: repository,
        removalCommand: removal,
        owner: _owner,
        currentOwner: () => currentOwner,
        args: const MyFriendsPageArgs(),
      );
      final load = controller.setActive(true);
      repository.succeed(0);
      await load;
      final pending = controller.removeFriend('202');
      currentOwner = (uid: '101', revision: 1);
      controller.dispose();
      expect(
        removal.requests.single.submission.cancellation!.isCancelled,
        isTrue,
      );
      removal.applied();
      await pending;
      expect(repository.requests, hasLength(1));
    },
  );

  test(
    'a hidden applied removal refreshes page one only on reactivation',
    () async {
      final repository = FriendFeedFixture();
      final removal = FriendRemovalFixture();
      final controller = _controller(
        repository,
        removal: removal,
        args: const MyFriendsPageArgs(initialPage: 3),
      );
      addTearDown(controller.dispose);
      final load = controller.setActive(true);
      repository.succeed(0);
      await load;
      final pending = controller.removeFriend('202');
      await controller.setActive(false);
      removal.applied();
      await pending;
      expect(repository.requests, hasLength(1));
      final resume = controller.setActive(true);
      expect(repository.requests.last.query.page, 1);
      repository.succeed(1, items: [], totalPages: 1, hasNext: false);
      await resume;
      expect(controller.value.currentPage, 1);
      expect(controller.value.data!.items, isEmpty);
    },
  );

  for (final wrongScope in [false, true]) {
    test(
      'a response for another ${wrongScope ? 'scope' : 'page'} cannot commit',
      () async {
        final repository = FriendFeedFixture();
        final controller = _controller(repository);
        addTearDown(controller.dispose);
        final pending = controller.setActive(true);
        repository.succeed(
          0,
          page: wrongScope ? 1 : 2,
          scope: wrongScope
              ? ForumFriendFeedScope.online
              : ForumFriendFeedScope.friends,
        );
        await pending;
        expect(controller.value.data, isNull);
        expect(
          controller.value.failure!.kind,
          DataReadFailureKind.unauthorized,
        );
      },
    );
  }

  for (final hide in [false, true]) {
    test(
      'cancelled pagination retains page one after ${hide ? 'hiding' : 'switching tabs'}',
      () async {
        final repository = FriendFeedFixture();
        final controller = _controller(repository);
        addTearDown(controller.dispose);
        final initial = controller.setActive(true);
        repository.succeed(0);
        await initial;
        final next = controller.loadNextPage();
        if (hide) {
          await controller.setActive(false);
        } else {
          final other = controller.selectScope(ForumFriendFeedScope.online);
          repository.succeed(2);
          await other;
        }
        expect(repository.requests[1].query.cancellation!.isCancelled, isTrue);
        repository.succeed(1, items: [friendFeedItem('303')]);
        await next;
        if (hide) {
          await controller.setActive(true);
        } else {
          await controller.selectScope(ForumFriendFeedScope.friends);
        }
        expect(controller.value.currentPage, 1);
        expect(controller.value.query.page, 1);
        final refresh = controller.refresh();
        expect(repository.requests.last.query.page, 1);
        repository.succeed(repository.requests.length - 1);
        await refresh;
        expect(controller.value.data!.items.single.userId, '202');
      },
    );
  }
}

MyFriendsController _controller(
  FriendFeedFixture repository, {
  FriendRemovalFixture? removal,
  VerifiedProfileOwner? owner = _owner,
  MyFriendsPageArgs args = const MyFriendsPageArgs(),
}) => MyFriendsController(
  repository: repository,
  removalCommand: removal ?? FriendRemovalFixture(),
  owner: owner,
  currentOwner: () => owner,
  args: args,
);
