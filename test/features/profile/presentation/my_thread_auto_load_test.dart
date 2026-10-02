import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/profile/data/providers/thread_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_card.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/thread_directory_fixture.dart';

void main() {
  for (final type in UserThreadDirectoryType.values) {
    testWidgets(
      '$type automatically pages near the bottom only once while busy',
      (tester) async {
        final host = await _mount(tester, initialType: type);
        final repository = host.repository;
        repository.succeed(0, items: _items(type, 30), hasMore: true);
        await _pumpFrames(tester);
        expect(repository.requests, hasLength(1));
        expect(find.byKey(const Key('my-thread-load-more')), findsNothing);

        final position = _position(tester, type);
        expect(position.extentAfter, greaterThan(400));
        // SliverList estimates unbuilt card extents. Leave enough margin for
        // that estimate to settle before checking either side of 300px.
        position.jumpTo(position.maxScrollExtent - 400);
        await _pumpFrames(tester);
        expect(position.extentAfter, greaterThan(300));
        expect(repository.requests, hasLength(1));

        position.jumpTo(position.maxScrollExtent - 200);
        await _pumpFrames(tester);
        expect(repository.requests, hasLength(2));
        _expectQuery(repository.requests.last, type: type, page: 2);
        expect(repository.requests.last.policy, CacheLoadPolicy.networkFirst);
        for (var i = 0; i < 3; i++) {
          position.jumpTo(position.maxScrollExtent);
          await _pumpFrames(tester);
        }
        expect(repository.requests, hasLength(2));

        repository.succeed(1, items: _items(type, 2, start: 100));
        await _pumpFrames(tester);
        position.jumpTo(position.maxScrollExtent);
        await _pumpFrames(tester);
        expect(repository.requests, hasLength(2));
        expect(
          find.text(_items(type, 2, start: 100).last.title),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$type fills short pages until content extends past the threshold',
      (tester) async {
        final host = await _mount(tester, initialType: type);
        final repository = host.repository;
        repository.succeed(0, items: _items(type, 1), hasMore: true);
        await _pumpFrames(tester);
        expect(repository.requests, hasLength(2));
        _expectQuery(repository.requests.last, type: type, page: 2);
        repository.succeed(
          1,
          items: _items(type, 1, start: 100),
          hasMore: true,
        );
        await _pumpFrames(tester);
        expect(repository.requests, hasLength(3));
        _expectQuery(repository.requests.last, type: type, page: 3);

        repository.succeed(
          2,
          items: _items(type, 30, start: 200),
          hasMore: true,
        );
        await _pumpFrames(tester, count: 12);
        expect(_position(tester, type).extentAfter, greaterThan(300));
        expect(repository.requests, hasLength(3));
        expect(find.text(_items(type, 1).single.title), findsOneWidget);
        expect(
          find.text(_items(type, 1, start: 100).single.title),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$type advances empty pages and stops when there is no next page',
      (tester) async {
        final host = await _mount(tester, initialType: type);
        final repository = host.repository;
        repository.succeed(0, items: const [], hasMore: true);
        await _pumpFrames(tester);
        expect(repository.requests, hasLength(2));
        _expectQuery(repository.requests.last, type: type, page: 2);
        repository.succeed(1, items: _items(type, 1), hasMore: true);
        await _pumpFrames(tester);
        expect(repository.requests, hasLength(3));
        _expectQuery(repository.requests.last, type: type, page: 3);

        repository.succeed(2, items: const []);
        await _pumpFrames(tester, count: 12);
        expect(repository.requests, hasLength(3));
        expect(find.text(_items(type, 1).single.title), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a viewport expansion alone schedules automatic pagination', (
    tester,
  ) async {
    final host = await _mount(tester, largeWindow: true);
    final repository = host.repository;
    repository.succeed(
      0,
      items: _items(UserThreadDirectoryType.threads, 30),
      hasMore: true,
    );
    await _pumpFrames(tester);
    final position = _position(tester, UserThreadDirectoryType.threads);
    position.jumpTo(position.maxScrollExtent - 400);
    await _pumpFrames(tester);
    expect(position.extentAfter, greaterThan(300));
    expect(position.extentAfter, lessThan(450));
    expect(repository.requests, hasLength(1));

    // A metrics notification after layout must arrange its own follow-up frame.
    // Pump only scheduled frames so a test-forced frame cannot hide that bug.
    host.viewportHeight.value = 800;
    await tester.pump();
    for (var i = 0; i < 8 && repository.requests.length == 1; i++) {
      if (!tester.binding.hasScheduledFrame) break;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.extentAfter, lessThanOrEqualTo(300));
    expect(repository.requests, hasLength(2));
    _expectQuery(
      repository.requests.last,
      type: UserThreadDirectoryType.threads,
      page: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a failed automatic page keeps data and waits for explicit retry even after changing tabs',
    (tester) async {
      final host = await _mount(tester);
      final repository = host.repository;
      final initial = _items(UserThreadDirectoryType.threads, 1);
      repository.succeed(0, items: initial, hasMore: true);
      await _pumpFrames(tester);
      expect(repository.requests, hasLength(2));
      repository.fail(1, DataReadFailureKind.network);
      await _pumpFrames(tester, count: 12);
      expect(find.text(initial.single.title), findsOneWidget);
      expect(find.text(_l10n(tester).commonNetworkError), findsOneWidget);
      expect(find.textContaining('raw server diagnostic'), findsNothing);
      expect(repository.requests, hasLength(2));

      await _selectTab(tester, UserThreadDirectoryType.replies);
      expect(repository.requests, hasLength(3));
      repository.succeed(2, items: _items(UserThreadDirectoryType.replies, 1));
      await _pumpFrames(tester);
      await _selectTab(tester, UserThreadDirectoryType.threads);
      await _pumpFrames(tester, count: 12);
      expect(repository.requests, hasLength(3));
      expect(find.text(initial.single.title), findsOneWidget);
      expect(find.text(_l10n(tester).commonNetworkError), findsOneWidget);

      await tester.tap(find.byKey(const Key('my-thread-retry')));
      await _pumpFrames(tester);
      expect(repository.requests, hasLength(4));
      _expectQuery(
        repository.requests.last,
        type: UserThreadDirectoryType.threads,
        page: 2,
      );
      final additional = _items(UserThreadDirectoryType.threads, 1, start: 100);
      repository.succeed(3, items: additional);
      await _pumpFrames(tester, count: 12);
      expect(find.text(initial.single.title), findsOneWidget);
      expect(find.text(additional.single.title), findsOneWidget);
      expect(find.byKey(const Key('my-thread-retry')), findsNothing);
      expect(repository.requests, hasLength(4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing tabs cancels automatic paging and discards its late result',
    (tester) async {
      final host = await _mount(tester);
      final repository = host.repository;
      final initial = _items(UserThreadDirectoryType.threads, 1);
      repository.succeed(0, items: initial, hasMore: true);
      await _pumpFrames(tester);
      expect(repository.requests, hasLength(2));
      final abandoned = repository.requests[1];

      await _selectTab(tester, UserThreadDirectoryType.replies);
      expect(abandoned.cancellation!.isCancelled, isTrue);
      expect(repository.requests, hasLength(3));
      _expectQuery(
        repository.requests.last,
        type: UserThreadDirectoryType.replies,
        page: 1,
      );
      final late = _items(UserThreadDirectoryType.threads, 1, start: 900);
      repository.succeed(1, items: late);
      repository.succeed(2, items: _items(UserThreadDirectoryType.replies, 1));
      await _pumpFrames(tester);
      expect(find.text(late.single.title, skipOffstage: false), findsNothing);

      await _selectTab(tester, UserThreadDirectoryType.threads);
      expect(repository.requests, hasLength(4));
      _expectQuery(
        repository.requests.last,
        type: UserThreadDirectoryType.threads,
        page: 2,
      );
      final fresh = _items(UserThreadDirectoryType.threads, 1, start: 100);
      repository.succeed(3, items: fresh);
      await _pumpFrames(tester);
      expect(find.text(initial.single.title), findsOneWidget);
      expect(find.text(fresh.single.title), findsOneWidget);
      expect(find.text(late.single.title, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a covered route cancels automatic paging and reloads on return',
    (tester) async {
      final host = await _mount(tester);
      final repository = host.repository;
      final initial = _items(UserThreadDirectoryType.threads, 1);
      repository.succeed(0, items: initial, hasMore: true);
      await _pumpFrames(tester);
      expect(repository.requests, hasLength(2));
      final abandoned = repository.requests[1];

      unawaited(
        host.navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Cover route')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpFrames(tester);
      expect(abandoned.cancellation!.isCancelled, isTrue);
      final late = _items(UserThreadDirectoryType.threads, 1, start: 900);
      repository.succeed(1, items: late);
      await _pumpFrames(tester, count: 12);
      expect(repository.requests, hasLength(2));

      host.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpFrames(tester);
      expect(repository.requests, hasLength(3));
      _expectQuery(
        repository.requests.last,
        type: UserThreadDirectoryType.threads,
        page: 2,
      );
      final fresh = _items(UserThreadDirectoryType.threads, 1, start: 100);
      repository.succeed(2, items: fresh);
      await _pumpFrames(tester);
      expect(find.text(initial.single.title), findsOneWidget);
      expect(find.text(fresh.single.title), findsOneWidget);
      expect(find.text(late.single.title, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final replacement in <VerifiedProfileOwner?>[
    (uid: '202', revision: 1),
    (uid: '101', revision: 1),
    null,
  ]) {
    testWidgets(
      'owner change to $replacement cancels and isolates automatic pages',
      (tester) async {
        final host = await _mount(tester);
        final repository = host.repository;
        final old = _items(UserThreadDirectoryType.threads, 1);
        repository.succeed(0, items: old, hasMore: true);
        await _pumpFrames(tester);
        expect(repository.requests, hasLength(2));
        final abandoned = repository.requests[1];

        host.container.updateOverrides([
          verifiedProfileOwnerProvider.overrideWithValue(replacement),
          userThreadDirectoryRepositoryProvider.overrideWithValue(repository),
        ]);
        await _pumpFrames(tester);
        expect(abandoned.cancellation!.isCancelled, isTrue);
        expect(find.text(old.single.title, skipOffstage: false), findsNothing);
        final late = _items(UserThreadDirectoryType.threads, 1, start: 900);
        repository.succeed(1, items: late);
        await _pumpFrames(tester);
        expect(find.text(late.single.title, skipOffstage: false), findsNothing);

        if (replacement == null) {
          expect(repository.requests, hasLength(2));
          expect(find.byType(UserThreadCard), findsNothing);
          expect(
            find.text(_l10n(tester).profileThreadsLoginRequired),
            findsOneWidget,
          );
        } else {
          expect(repository.requests, hasLength(3));
          _expectQuery(
            repository.requests.last,
            type: UserThreadDirectoryType.threads,
            page: 1,
            uid: replacement.uid,
          );
          final fresh = _items(UserThreadDirectoryType.threads, 1, start: 200);
          repository.succeed(2, items: fresh);
          await _pumpFrames(tester, count: 12);
          expect(find.text(fresh.single.title), findsOneWidget);
          expect(
            find.text(old.single.title, skipOffstage: false),
            findsNothing,
          );
          expect(
            find.text(late.single.title, skipOffstage: false),
            findsNothing,
          );
          expect(repository.requests, hasLength(3));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<_ThreadTestHost> _mount(
  WidgetTester tester, {
  UserThreadDirectoryType initialType = UserThreadDirectoryType.threads,
  bool largeWindow = false,
}) async {
  tester.view.physicalSize = Size(360, largeWindow ? 900 : 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final host = _ThreadTestHost();
  addTearDown(host.container.dispose);
  addTearDown(host.viewportHeight.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: host.container,
      child: LocalizedTestApp(
        theme: AppTheme.light(),
        navigatorKey: host.navigator,
        home: ValueListenableBuilder<double>(
          valueListenable: host.viewportHeight,
          child: UserThreadPage(initialType: initialType),
          builder: (_, height, child) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(height: height, child: child),
          ),
        ),
      ),
    ),
  );
  await _pumpFrames(tester);
  expect(host.repository.requests, hasLength(1));
  _expectQuery(host.repository.requests.single, type: initialType, page: 1);
  return host;
}

final class _ThreadTestHost {
  _ThreadTestHost() {
    container = ProviderContainer(
      overrides: [
        verifiedProfileOwnerProvider.overrideWithValue((
          uid: '101',
          revision: 0,
        )),
        userThreadDirectoryRepositoryProvider.overrideWithValue(repository),
      ],
    );
  }

  final repository = ThreadDirectoryFixture();
  final navigator = GlobalKey<NavigatorState>();
  final viewportHeight = ValueNotifier<double>(640);
  late final ProviderContainer container;
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 4}) async {
  // Pending fixture reads deliberately keep a spinner alive; settling would
  // wait forever instead of exercising the cancellation or single-flight path.
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _selectTab(
  WidgetTester tester,
  UserThreadDirectoryType type,
) async {
  final l10n = _l10n(tester);
  await tester.tap(
    find.text(
      type == UserThreadDirectoryType.threads
          ? l10n.profileMyThreadsTab
          : l10n.profileMyRepliesTab,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await _pumpFrames(tester);
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(UserThreadPage)));

ScrollPosition _position(WidgetTester tester, UserThreadDirectoryType type) {
  final refresh = find.byKey(Key('my-thread-refresh-${type.name}'));
  final scroll = find.descendant(
    of: refresh,
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scroll).position;
}

void _expectQuery(
  ThreadDirectoryRequest request, {
  required UserThreadDirectoryType type,
  required int page,
  String uid = '101',
}) => expect(
  request.query,
  UserThreadDirectoryQuery(
    userId: uid,
    viewerUserId: uid,
    type: type,
    page: page,
  ),
);

List<UserThreadSummary> _items(
  UserThreadDirectoryType type,
  int count, {
  int start = 1,
}) => [
  for (var index = 0; index < count; index++)
    UserThreadSummary(
      threadId: '${start + index}',
      title: '${type.name} row ${start + index}',
      uri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=${start + index}',
      ),
      replyPreviews: [
        if (type == UserThreadDirectoryType.replies)
          UserThreadReplyPreview(
            postId: '${start + index + 1000}',
            excerpt: 'Reply ${start + index}',
            uri: Uri.parse(
              'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=${start + index}&pid=${start + index + 1000}',
            ),
          ),
      ],
    ),
];
