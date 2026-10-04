import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/profile/data/providers/thread_read_providers.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_card.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_page.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/thread_directory_fixture.dart';

void main() {
  testWidgets(
    'another owner uses the shared reply tab and preserves separate PIDs',
    (tester) async {
      final repository = ThreadDirectoryFixture(autoComplete: true);
      final opened = <String?>[];
      await _mount(
        tester,
        repository,
        page: UserThreadPage(
          userId: '202',
          initialType: UserThreadDirectoryType.replies,
          initialPage: 3,
          onOpenThread: (_, _, reply) => opened.add(reply?.postId),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);
      expect(find.text(l10n.profileUserThreadsTitle), findsOneWidget);
      expect(
        repository.requests.single.query,
        const UserThreadDirectoryQuery(
          userId: '202',
          viewerUserId: '101',
          type: UserThreadDirectoryType.replies,
          page: 3,
        ),
      );
      await tester.tap(find.byKey(const Key('my-thread-reply-502')));
      expect(opened, ['502']);
      await tester.tap(find.text(l10n.profileMyThreadsTab));
      await tester.pumpAndSettle();
      expect(
        repository.requests.last.query.type,
        UserThreadDirectoryType.threads,
      );
      expect(repository.requests.last.query.page, 1);
      await tester.tap(find.text(l10n.profileMyRepliesTab));
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(2));
      expect(find.byKey(const Key('my-thread-reply-501')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final update in <String, UserThreadPage>{
    'target': const UserThreadPage(userId: '303', initialPage: 3),
    'type': const UserThreadPage(
      userId: '202',
      initialType: UserThreadDirectoryType.replies,
      initialPage: 3,
    ),
    'page': const UserThreadPage(userId: '202', initialPage: 5),
  }.entries) {
    testWidgets(
      'changing URL ${update.key} cancels the previous read and rejects its late result',
      (tester) async {
        final repository = ThreadDirectoryFixture();
        final page = ValueNotifier(
          const UserThreadPage(userId: '202', initialPage: 3),
        );
        addTearDown(page.dispose);
        await _mount(
          tester,
          repository,
          page: ValueListenableBuilder<UserThreadPage>(
            valueListenable: page,
            builder: (_, value, _) => value,
          ),
        );
        await _pumpFrames(tester);
        page.value = update.value;
        await _pumpFrames(tester);
        expect(repository.requests, hasLength(2));
        expect(repository.requests.first.cancellation!.isCancelled, isTrue);
        expect(
          repository.requests.last.query,
          UserThreadDirectoryQuery(
            userId: update.value.userId!,
            viewerUserId: '101',
            type: update.value.initialType,
            page: update.value.initialPage,
          ),
        );
        repository.succeed(0, items: [threadSummary('stale')]);
        await _pumpFrames(tester);
        expect(find.text(threadSummary('stale').title), findsNothing);
        repository.succeed(1, items: [threadSummary('fresh')]);
        await tester.pumpAndSettle();
        expect(find.text(threadSummary('fresh').title), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final transition in <String, VerifiedSessionOwner?>{
    'viewer account': (uid: '303', revision: 1),
    'same account session': (uid: '101', revision: 1),
    'logout': null,
  }.entries) {
    testWidgets(
      '${transition.key} change cancels an other-user read without changing its target',
      (tester) async {
        final repository = ThreadDirectoryFixture();
        final container = await _mount(tester, repository);
        await _pumpFrames(tester);
        container.updateOverrides(_overrides(repository, transition.value));
        await _pumpFrames(tester);
        expect(repository.requests.first.cancellation!.isCancelled, isTrue);
        repository.succeed(0, items: [threadSummary('stale')]);
        await _pumpFrames(tester);
        expect(find.text(threadSummary('stale').title), findsNothing);
        if (transition.value == null) {
          expect(repository.requests, hasLength(1));
          expect(
            find.text(_l10n(tester).profileUserThreadsLoginRequired),
            findsOneWidget,
          );
        } else {
          expect(repository.requests, hasLength(2));
          expect(repository.requests.last.query.userId, '202');
          expect(
            repository.requests.last.query.viewerUserId,
            transition.value!.uid,
          );
          repository.succeed(1, items: [threadSummary('fresh')]);
          await tester.pumpAndSettle();
          expect(find.text(threadSummary('fresh').title), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'retargeting rejects callbacks and pending reply navigation from the previous owner',
    (tester) async {
      final repository = ThreadDirectoryFixture(autoComplete: true);
      final locator = _PendingLocator();
      final page = ValueNotifier(
        const UserThreadPage(
          userId: '202',
          initialType: UserThreadDirectoryType.replies,
        ),
      );
      addTearDown(page.dispose);
      await _mount(
        tester,
        repository,
        locator: locator,
        page: ValueListenableBuilder<UserThreadPage>(
          valueListenable: page,
          builder: (_, value, _) => value,
        ),
      );
      await tester.pumpAndSettle();
      final old = tester.widget<UserThreadCard>(find.byType(UserThreadCard));
      await tester.tap(find.byKey(const Key('my-thread-reply-502')));
      await tester.pumpAndSettle();
      expect(locator.targets.single, (tid: '100', pid: '502'));
      expect(locator.sourceUri!.queryParameters['pid'], '502');
      page.value = const UserThreadPage(
        userId: '303',
        initialType: UserThreadDirectoryType.replies,
      );
      await tester.pumpAndSettle();
      old.onOpenReply(old.item.replyPreviews.first);
      expect(locator.targets, hasLength(1));
      locator.pending.complete(
        const ApiSuccess(
          ThreadPostLocation(tid: '100', pid: '502', page: 3, url: ''),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ThreadDetailPage), findsNothing);
      expect(repository.requests.last.query.userId, '303');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a guest sees the other-user Traditional Chinese prompt on a narrow large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = ThreadDirectoryFixture();
      await _mount(
        tester,
        repository,
        owner: null,
        locale: const Locale('zh', 'TW'),
        scale: 1.8,
      );
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);
      expect(find.text(l10n.profileUserThreadsTitle), findsOneWidget);
      expect(find.text(l10n.profileUserThreadsLoginRequired), findsOneWidget);
      expect(find.text(l10n.authLoginTitle), findsOneWidget);
      expect(repository.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  ThreadDirectoryFixture repository, {
  Widget page = const UserThreadPage(userId: '202'),
  VerifiedSessionOwner? owner = (uid: '101', revision: 0),
  _PendingLocator? locator,
  Locale locale = const Locale('zh'),
  double scale = 1,
}) async {
  final container = ProviderContainer(
    overrides: [
      ..._overrides(repository, owner),
      if (locator != null) threadPostLocatorProvider.overrideWithValue(locator),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: LocalizedTestApp(
        theme: AppTheme.light(),
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  return container;
}

List<Override> _overrides(
  ThreadDirectoryFixture repository,
  VerifiedSessionOwner? owner,
) => [
  verifiedSessionOwnerProvider.overrideWithValue(owner),
  userThreadDirectoryRepositoryProvider.overrideWithValue(repository),
];

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(UserThreadPage)));

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

final class _PendingLocator implements ThreadPostLocator {
  final pending = Completer<ApiResult<ThreadPostLocation>>();
  final targets = <({String tid, String pid})>[];
  Uri? sourceUri;

  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) {
    targets.add((tid: tid, pid: pid));
    this.sourceUri = sourceUri;
    return pending.future;
  }
}
