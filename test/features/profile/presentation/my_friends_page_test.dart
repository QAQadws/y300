import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/data/providers/friend_read_providers.dart';
import 'package:y300/features/profile/presentation/friends/my_friends_page.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/native_pagination_bar.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/friend_read_fixture.dart';

final _ownerSource = StateProvider<VerifiedSessionOwner?>(
  (_) => (uid: '101', revision: 0),
);

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('friend title and four tabs use $locale localizations', (
      tester,
    ) async {
      final repository = FriendFeedFixture(autoComplete: true);
      await _pumpPage(tester, repository: repository, locale: locale);
      final l10n = _l10n(tester);
      expect(find.text(l10n.profileMyFriendsTitle), findsOneWidget);
      expect(find.text(l10n.profileFriendsTab), findsOneWidget);
      expect(find.text(l10n.profileFriendsOnlineTab), findsOneWidget);
      expect(find.text(l10n.profileFriendsVisitorsTab), findsOneWidget);
      expect(find.text(l10n.profileFriendsFootprintsTab), findsOneWidget);
      expect(repository.requests, hasLength(1));
      expect(
        repository.requests.single.query.scope,
        ForumFriendFeedScope.friends,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('inactive page defers reading until it becomes visible', (
    tester,
  ) async {
    final repository = FriendFeedFixture(autoComplete: true);
    final removal = FriendRemovalFixture();
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(repository, removal),
        child: LocalizedTestApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (context, isActive, child) => _page(isActive: isActive),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.requests, isEmpty);
    active.value = true;
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(1));
    active.value = false;
    await tester.pumpAndSettle();
    active.value = true;
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(1));
  });

  testWidgets('tap and swipe load each scope lazily and retain visited rows', (
    tester,
  ) async {
    final repository = FriendFeedFixture(autoComplete: true);
    await _pumpPage(tester, repository: repository);
    final l10n = _l10n(tester);
    await tester.tap(find.text(l10n.profileFriendsVisitorsTab));
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(2));
    expect(repository.requests.last.query.scope, ForumFriendFeedScope.visitors);
    final pager = find.byType(TabBarView);
    await tester.drag(pager, Offset(-tester.getSize(pager).width * .8, 0));
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(3));
    expect(
      repository.requests.last.query.scope,
      ForumFriendFeedScope.footprints,
    );
    await tester.tap(find.text(l10n.profileFriendsTab));
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(3));
    expect(_scopeList(ForumFriendFeedScope.friends), findsOneWidget);
    expect(find.byKey(const Key('my-friends-user-202')), findsOneWidget);
  });

  for (final scope in ForumFriendFeedScope.values) {
    testWidgets(
      'every card region in $scope dispatches the source profile link exactly once',
      (tester) async {
        final repository = _metadataRepository();
        final removal = FriendRemovalFixture();
        final links = <String>[];
        final conversations =
            <({ForumConversationTarget target, String title})>[];
        await _pumpPage(
          tester,
          repository: repository,
          removal: removal,
          page: MyFriendsPage(
            initialScope: scope,
            onOpenLink: (_, url) => links.add(url),
            onOpenConversation: (_, target, title) =>
                conversations.add((target: target, title: title)),
          ),
        );
        final l10n = _l10n(tester);
        expect(repository.requests.single.query.scope, scope);
        expect(find.text(_friendName), findsOneWidget);
        expect(find.text(_friendNote), findsOneWidget);
        expect(find.text(l10n.profileFriendsOnlineStatus), findsOneWidget);
        expect(
          find.text(l10n.profileFriendsVisitedAt(_friendVisitedAt)),
          findsOneWidget,
        );
        expect(find.byKey(const Key('my-friends-message-202')), findsNothing);
        expect(find.byKey(const Key('my-friends-remove-202')), findsNothing);

        for (final region in _friendRegions) {
          links.clear();
          await _gestureFriendRegion(tester, region);
          await tester.pumpAndSettle();

          expect(
            links,
            [_friendProfileUrl],
            reason: '$scope $region must dispatch the source profile link once',
          );
          expect(
            conversations,
            isEmpty,
            reason: '$scope $region must not send PM',
          );
          expect(removal.requests, isEmpty);
          expect(
            find.byKey(const Key('my-friends-actions-sheet')),
            findsNothing,
          );
          expect(repository.requests, hasLength(1));
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'a friend without a source profile link can only use its long press actions',
    (tester) async {
      final repository = FriendFeedFixture(autoComplete: true)
        ..items = const [
          ForumFriendFeedItem(
            userId: '202',
            username: _friendName,
            profileUrl: null,
            note: _friendNote,
            visitedAtText: _friendVisitedAt,
            isOnline: true,
            canRemove: true,
          ),
        ];
      final removal = FriendRemovalFixture();
      final links = <String>[];
      final conversations = <ForumConversationTarget>[];
      await _pumpPage(
        tester,
        repository: repository,
        removal: removal,
        page: MyFriendsPage(
          onOpenLink: (_, url) => links.add(url),
          onOpenConversation: (_, target, _) => conversations.add(target),
        ),
      );

      for (final region in _friendRegions) {
        await _gestureFriendRegion(tester, region);
        await tester.pumpAndSettle();
        expect(links, isEmpty);
        expect(conversations, isEmpty);
        expect(find.byKey(const Key('my-friends-actions-sheet')), findsNothing);
      }
      await _openActions(tester);
      expect(find.byKey(const Key('my-friends-message-202')), findsOneWidget);
      expect(find.byKey(const Key('my-friends-remove-202')), findsOneWidget);
      await tester.tap(find.byKey(const Key('my-friends-message-202')));
      await tester.pumpAndSettle();
      expect(links, isEmpty);
      expect(conversations, [const ForumConversationTarget.direct('202')]);
      expect(removal.requests, isEmpty);
      expect(repository.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('anonymous visitors have no profile or long press actions', (
    tester,
  ) async {
    final repository = FriendFeedFixture(autoComplete: true)
      ..items = const [
        ForumFriendFeedItem(userId: '', username: '', profileUrl: null),
      ];
    final removal = FriendRemovalFixture();
    final links = <String>[];
    final conversations = <ForumConversationTarget>[];
    await _pumpPage(
      tester,
      repository: repository,
      removal: removal,
      page: MyFriendsPage(
        initialScope: ForumFriendFeedScope.visitors,
        onOpenLink: (_, url) => links.add(url),
        onOpenConversation: (_, target, _) => conversations.add(target),
      ),
    );
    expect(find.text(_l10n(tester).profileFriendsAnonymous), findsOneWidget);
    final card = find.byKey(const Key('my-friends-anonymous-0'));
    await tester.tap(card);
    await tester.longPress(card);
    await tester.pumpAndSettle();

    expect(links, isEmpty);
    expect(conversations, isEmpty);
    expect(removal.requests, isEmpty);
    expect(find.byKey(const Key('my-friends-actions-sheet')), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'four scopes share a page label while known totals retain distant page selection',
    (tester) async {
      final repository = FriendFeedFixture(autoComplete: true)..totalPages = 18;
      await _pumpPage(tester, repository: repository);
      final l10n = _l10n(tester);

      for (final scope in ForumFriendFeedScope.values) {
        final totalPages = scope == ForumFriendFeedScope.friends ? 18 : null;
        repository.totalPages = totalPages;
        if (scope != ForumFriendFeedScope.friends) {
          await tester.tap(find.text(_scopeLabel(l10n, scope)));
          await tester.pumpAndSettle();
        }
        expect(repository.requests.last.query.scope, scope);
        expect(find.byType(NativePaginationBar), findsOneWidget);
        final bar = tester.widget<NativePaginationBar>(
          find.byType(NativePaginationBar),
        );
        expect(bar.currentPage, 1);
        expect(bar.currentLabel, l10n.commonPage(1));
        expect(bar.lastPage, totalPages);
        expect(find.text(l10n.commonPage(1)), findsOneWidget);
        expect(
          find.byKey(const Key('my-friends-page-previous')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('my-friends-page-current')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('my-friends-page-next')), findsOneWidget);
      }

      await tester.tap(find.text(l10n.profileFriendsTab));
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(4));
      repository.totalPages = 18;
      await tester.tap(find.byKey(const Key('my-friends-page-current')));
      await tester.pumpAndSettle();
      final lastPageOption = find.byKey(
        const Key('my-friends-page-page-option-18'),
      );
      final menuScrollable = find.descendant(
        of: find.byKey(const Key('my-friends-page-page-list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        lastPageOption,
        200,
        scrollable: menuScrollable,
      );
      await tester.ensureVisible(lastPageOption);
      await tester.pumpAndSettle();
      await tester.tap(lastPageOption);
      await tester.pumpAndSettle();

      expect(repository.requests, hasLength(5));
      expect(
        repository.requests.last.query.scope,
        ForumFriendFeedScope.friends,
      );
      expect(repository.requests.last.query.page, 18);
      final bar = tester.widget<NativePaginationBar>(
        find.byType(NativePaginationBar),
      );
      expect(bar.currentLabel, l10n.commonPage(18));
      expect(bar.lastPage, 18);
      expect(bar.hasMore, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pagination replaces the current page and remembers each scope cursor',
    (tester) async {
      final repository = FriendFeedFixture(autoComplete: true);
      await _pumpPage(tester, repository: repository);
      expect(find.byType(NativePaginationBar), findsOneWidget);
      await tester.tap(find.byKey(const Key('my-friends-page-next')));
      await tester.pumpAndSettle();
      expect(repository.requests.last.query.page, 2);
      final l10n = _l10n(tester);
      await tester.tap(find.text(l10n.profileFriendsOnlineTab));
      await tester.pumpAndSettle();
      expect(repository.requests.last.query.scope, ForumFriendFeedScope.online);
      expect(repository.requests.last.query.page, 1);
      await tester.tap(find.text(l10n.profileFriendsTab));
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(3));
      await tester.tap(find.byKey(const Key('my-friends-page-previous')));
      await tester.pumpAndSettle();
      expect(
        repository.requests.last.query.scope,
        ForumFriendFeedScope.friends,
      );
      expect(repository.requests.last.query.page, 1);
    },
  );

  for (final region in _friendRegions) {
    testWidgets(
      'friends long press on $region opens actions without navigating',
      (tester) async {
        final repository = _metadataRepository();
        final removal = FriendRemovalFixture();
        final links = <String>[];
        final conversations =
            <({ForumConversationTarget target, String title})>[];
        await _pumpPage(
          tester,
          repository: repository,
          removal: removal,
          page: MyFriendsPage(
            onOpenLink: (_, url) => links.add(url),
            onOpenConversation: (_, target, title) =>
                conversations.add((target: target, title: title)),
          ),
        );
        await _openActions(tester, target: region);
        expect(links, isEmpty);
        expect(conversations, isEmpty);
        expect(removal.requests, isEmpty);
        expect(find.byKey(const Key('my-friends-message-202')), findsOneWidget);
        expect(find.byKey(const Key('my-friends-remove-202')), findsOneWidget);
        await tester.tap(find.byKey(const Key('my-friends-message-202')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('my-friends-actions-sheet')), findsNothing);
        expect(links, isEmpty);
        expect(conversations, [
          (
            target: const ForumConversationTarget.direct('202'),
            title: _friendName,
          ),
        ]);
        expect(removal.requests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scope in ForumFriendFeedScope.values.where(
    (scope) => scope != ForumFriendFeedScope.friends,
  )) {
    testWidgets('$scope long presses offer messaging without removal', (
      tester,
    ) async {
      final repository = _metadataRepository();
      final removal = FriendRemovalFixture();
      final links = <String>[];
      final conversations =
          <({ForumConversationTarget target, String title})>[];
      await _pumpPage(
        tester,
        repository: repository,
        removal: removal,
        page: MyFriendsPage(
          initialScope: scope,
          onOpenLink: (_, url) => links.add(url),
          onOpenConversation: (_, target, title) =>
              conversations.add((target: target, title: title)),
        ),
      );
      expect(repository.requests.single.query.scope, scope);
      expect(repository.items.single.canRemove, isTrue);

      for (final region in _friendRegions) {
        conversations.clear();
        await _openActions(tester, target: region);
        expect(
          links,
          isEmpty,
          reason: '$scope $region must not open a profile',
        );
        expect(conversations, isEmpty);
        expect(removal.requests, isEmpty);
        expect(find.byKey(const Key('my-friends-message-202')), findsOneWidget);
        expect(find.byKey(const Key('my-friends-remove-202')), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);

        await tester.tap(find.byKey(const Key('my-friends-message-202')));
        await tester.pumpAndSettle();

        expect(conversations, [
          (
            target: const ForumConversationTarget.direct('202'),
            title: _friendName,
          ),
        ]);
        expect(links, isEmpty);
        expect(removal.requests, isEmpty);
        expect(find.byKey(const Key('my-friends-actions-sheet')), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(repository.requests, hasLength(1));
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final nextOwner in <VerifiedSessionOwner?>[
    (uid: '999', revision: 1),
    (uid: '101', revision: 1),
    null,
  ]) {
    testWidgets('owner transition to $nextOwner dismisses account actions', (
      tester,
    ) async {
      final repository = FriendFeedFixture(autoComplete: true);
      final removal = FriendRemovalFixture();
      final overrides = _overrides(repository, removal);
      overrides[0] = verifiedSessionOwnerProvider.overrideWith(
        (ref) => ref.watch(_ownerSource),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: LocalizedTestApp(home: _page()),
        ),
      );
      await tester.pumpAndSettle();
      await _openActions(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MyFriendsPage)),
      );
      container.read(_ownerSource.notifier).state = nextOwner;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-friends-actions-sheet')), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(removal.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in ['message', 'remove']) {
    testWidgets(
      'a sheet $action selection cannot run after the session changes',
      (tester) async {
        final repository = FriendFeedFixture(autoComplete: true);
        final removal = FriendRemovalFixture();
        final links = <String>[];
        final conversations = <ForumConversationTarget>[];
        final overrides = _overrides(repository, removal);
        overrides[0] = verifiedSessionOwnerProvider.overrideWith(
          (ref) => ref.watch(_ownerSource),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: overrides,
            child: LocalizedTestApp(
              home: MyFriendsPage(
                onOpenLink: (_, url) => links.add(url),
                onOpenConversation: (_, target, _) => conversations.add(target),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _openActions(tester);
        final staleSelection = tester
            .widget<ListTile>(find.byKey(Key('my-friends-$action-202')))
            .onTap!;
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MyFriendsPage)),
        );
        container.read(_ownerSource.notifier).state = (uid: '101', revision: 1);
        // Select the still-mounted tile before the next frame removes the sheet.
        staleSelection();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('my-friends-actions-sheet')), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(removal.requests, isEmpty);
        expect(links, isEmpty);
        expect(conversations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'removal requires confirmation and only applied updates the displayed list',
    (tester) async {
      final repository = FriendFeedFixture(autoComplete: true);
      final removal = FriendRemovalFixture();
      await _pumpPage(tester, repository: repository, removal: removal);
      await _openRemovalConfirmation(tester);
      expect(removal.requests, isEmpty);
      await tester.tap(find.byKey(const Key('my-friends-remove-cancel')));
      await tester.pumpAndSettle();
      expect(removal.requests, isEmpty);
      await _openRemovalConfirmation(tester);
      await tester.tap(find.byKey(const Key('my-friends-remove-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(removal.requests.single.submission.actorUserId, '101');
      expect(removal.requests.single.submission.userId, '202');
      expect(repository.requests, hasLength(1));
      repository.items = [];
      removal.applied();
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(2));
      expect(find.byKey(const Key('my-friends-user-202')), findsNothing);
      expect(find.text(_l10n(tester).profileFriendsRemoved), findsOneWidget);
    },
  );

  testWidgets(
    'uncertain removal keeps the row locked and shows localized guidance',
    (tester) async {
      final repository = FriendFeedFixture(autoComplete: true);
      final removal = FriendRemovalFixture();
      await _pumpPage(tester, repository: repository, removal: removal);
      await _openRemovalConfirmation(tester);
      await tester.tap(find.byKey(const Key('my-friends-remove-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      removal.outcomeUnknown();
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(1));
      expect(removal.requests, hasLength(1));
      expect(find.byKey(const Key('my-friends-user-202')), findsOneWidget);
      expect(
        find.text(_l10n(tester).profileFriendRemovalUnknown),
        findsOneWidget,
      );
      expect(find.textContaining('private server payload'), findsNothing);
      await _expectRemovalAction(tester, enabled: false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'guest page gives a localized login action without network work',
    (tester) async {
      final repository = FriendFeedFixture(autoComplete: true);
      await _pumpPage(tester, repository: repository, owner: null);
      expect(repository.requests, isEmpty);
      expect(
        find.text(_l10n(tester).profileFriendsLoginRequired),
        findsOneWidget,
      );
      expect(find.byKey(const Key('my-friends-login')), findsOneWidget);
    },
  );

  testWidgets(
    'unknown removal guidance survives tab changes until manual verification',
    (tester) async {
      final repository = FriendFeedFixture(autoComplete: true);
      final removal = FriendRemovalFixture();
      await _pumpPage(tester, repository: repository, removal: removal);
      await _openRemovalConfirmation(tester);
      await tester.tap(find.byKey(const Key('my-friends-remove-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      removal.outcomeUnknown();
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);
      await tester.tap(find.text(l10n.profileFriendsOnlineTab));
      await tester.pumpAndSettle();
      expect(repository.requests.last.query.scope, ForumFriendFeedScope.online);
      await tester.tap(find.text(l10n.profileFriendsTab));
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(2));
      expect(
        find.byKey(const Key('my-friends-removal-verification')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('my-friends-removal-verify')));
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(3));
      expect(
        repository.requests.last.query.scope,
        ForumFriendFeedScope.friends,
      );
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabs.controller!.index, ForumFriendFeedScope.friends.index);
      await _expectRemovalAction(tester, enabled: true);
    },
  );

  testWidgets(
    'uncertain removal while covered stays visible until a manual verification',
    (tester) async {
      final repository = FriendFeedFixture(autoComplete: true);
      final removal = FriendRemovalFixture();
      await _pumpPage(
        tester,
        repository: repository,
        removal: removal,
        page: MyFriendsPage(
          onOpenLink: (context, url) => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                key: const Key('friend-test-user-route'),
                appBar: AppBar(),
                body: Text(url),
              ),
            ),
          ),
          onOpenConversation: (_, _, _) {},
        ),
      );
      await _openRemovalConfirmation(tester);
      await tester.tap(find.byKey(const Key('my-friends-remove-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(removal.requests, hasLength(1));
      await tester.tap(find.byKey(const Key('my-friends-name-202')));
      await tester.pumpAndSettle();
      removal.outcomeUnknown();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('friend-test-user-route')), findsOneWidget);
      expect(repository.requests, hasLength(1));
      Navigator.of(
        tester.element(find.byKey(const Key('friend-test-user-route'))),
      ).pop();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('my-friends-removal-verification')),
        findsOneWidget,
      );
      await _expectRemovalAction(tester, enabled: false);
      await tester.tap(find.byKey(const Key('my-friends-removal-verify')));
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(2));
      expect(
        find.byKey(const Key('my-friends-removal-verification')),
        findsNothing,
      );
      await _expectRemovalAction(tester, enabled: true);
    },
  );

  testWidgets(
    'a same UID session change dismisses the old removal confirmation',
    (tester) async {
      final repository = FriendFeedFixture(autoComplete: true);
      final removal = FriendRemovalFixture();
      final overrides = _overrides(repository, removal);
      overrides[0] = verifiedSessionOwnerProvider.overrideWith(
        (ref) => ref.watch(_ownerSource),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: LocalizedTestApp(home: _page()),
        ),
      );
      await tester.pumpAndSettle();
      await _openRemovalConfirmation(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MyFriendsPage)),
      );
      container.read(_ownerSource.notifier).state = (uid: '101', revision: 1);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(removal.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed first page retries explicitly without showing diagnostic text',
    (tester) async {
      final repository = FriendFeedFixture();
      await _pumpPage(tester, repository: repository, settle: false);
      await tester.pump();
      repository.fail(0, DataReadFailureKind.network);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-friends-retry')), findsOneWidget);
      expect(find.textContaining('fixture_failure'), findsNothing);
      await tester.tap(find.byKey(const Key('my-friends-retry')));
      await tester.pump();
      expect(repository.requests, hasLength(2));
      repository.succeed(1);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-friends-user-202')), findsOneWidget);
    },
  );

  testWidgets('friend cards and tabs fit 300dp with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FriendFeedFixture(autoComplete: true);
    repository.items = [
      friendFeedItem(
        '202',
        username: 'A long member name for narrow layouts',
        note: 'A long status with enough text to wrap onto several lines.',
        visitedAtText: '2026-10-03 10:00',
        isOnline: true,
      ),
    ];
    await _pumpPage(tester, repository: repository, textScale: 1.8);
    expect(find.byKey(const Key('my-friends-user-202')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _openActions(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('my-friends-remove-202')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my-friends-remove-confirm')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

MyFriendsPage _page({bool isActive = true}) => MyFriendsPage(
  isActive: isActive,
  onOpenLink: (_, _) {},
  onOpenConversation: (_, _, _) {},
);

List<Override> _overrides(
  FriendFeedFixture repository,
  FriendRemovalFixture removal, {
  VerifiedSessionOwner? owner = (uid: '101', revision: 0),
}) => [
  verifiedSessionOwnerProvider.overrideWithValue(owner),
  friendFeedRepositoryProvider.overrideWithValue(repository),
  friendRemovalCommandProvider.overrideWithValue(removal),
  forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
];

Future<void> _pumpPage(
  WidgetTester tester, {
  required FriendFeedFixture repository,
  FriendRemovalFixture? removal,
  MyFriendsPage? page,
  Locale locale = const Locale('zh'),
  VerifiedSessionOwner? owner = (uid: '101', revision: 0),
  bool settle = true,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        repository,
        removal ?? FriendRemovalFixture(),
        owner: owner,
      ),
      child: LocalizedTestApp(
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: page ?? _page(),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MyFriendsPage)));

Finder _scopeList(ForumFriendFeedScope scope) => find.byWidgetPredicate(
  (widget) =>
      widget is CustomScrollView &&
      widget.key is PageStorageKey<String> &&
      (widget.key! as PageStorageKey<String>).value.startsWith(
        'my-friends-list-${scope.name}:',
      ),
);

String _scopeLabel(AppLocalizations l10n, ForumFriendFeedScope scope) =>
    switch (scope) {
      ForumFriendFeedScope.friends => l10n.profileFriendsTab,
      ForumFriendFeedScope.online => l10n.profileFriendsOnlineTab,
      ForumFriendFeedScope.visitors => l10n.profileFriendsVisitorsTab,
      ForumFriendFeedScope.footprints => l10n.profileFriendsFootprintsTab,
    };

const _friendProfileUrl =
    'https://bbs.yamibo.com/home.php?mod=space&uid=202&mobile=2&from=friend-list';
const _friendName = 'Alice';
const _friendNote = 'Server note';
const _friendVisitedAt = '2026-10-03 10:00';
const _friendRegions = [
  'user',
  'avatar',
  'name',
  'status',
  'note',
  'visitedAt',
  'padding',
];

FriendFeedFixture _metadataRepository() =>
    FriendFeedFixture(autoComplete: true)
      ..items = [
        friendFeedItem(
          '202',
          username: _friendName,
          profileUrl: _friendProfileUrl,
          note: _friendNote,
          visitedAtText: _friendVisitedAt,
          isOnline: true,
        ),
      ];

Future<void> _gestureFriendRegion(
  WidgetTester tester,
  String region, {
  bool longPress = false,
}) async {
  if (region == 'padding') {
    final card = find.byKey(const Key('my-friends-user-202'));
    final point = tester.getBottomRight(card) - const Offset(6, 6);
    if (longPress) {
      await tester.longPressAt(point);
    } else {
      await tester.tapAt(point);
    }
    return;
  }
  final finder = switch (region) {
    'status' => find.text(_l10n(tester).profileFriendsOnlineStatus),
    'note' => find.text(_friendNote),
    'visitedAt' => find.text(
      _l10n(tester).profileFriendsVisitedAt(_friendVisitedAt),
    ),
    _ => find.byKey(Key('my-friends-$region-202')),
  };
  if (longPress) {
    await tester.longPress(finder);
  } else {
    await tester.tap(finder);
  }
}

Future<void> _openActions(WidgetTester tester, {String target = 'user'}) async {
  await _gestureFriendRegion(tester, target, longPress: true);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('my-friends-actions-sheet')), findsOneWidget);
}

Future<void> _openRemovalConfirmation(WidgetTester tester) async {
  await _openActions(tester);
  await tester.tap(find.byKey(const Key('my-friends-remove-202')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('my-friends-actions-sheet')), findsNothing);
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> _expectRemovalAction(
  WidgetTester tester, {
  required bool enabled,
}) async {
  await _openActions(tester);
  expect(
    find.byKey(const Key('my-friends-remove-202')),
    enabled ? findsOneWidget : findsNothing,
  );
  Navigator.of(
    tester.element(find.byKey(const Key('my-friends-actions-sheet'))),
  ).pop();
  await tester.pumpAndSettle();
}
