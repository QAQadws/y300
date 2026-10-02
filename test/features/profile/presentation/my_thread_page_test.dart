import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/profile/data/providers/thread_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_card.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_page.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';
import 'package:y300/shared/widgets/forum_pull_to_refresh.dart';
import 'package:y300/shared/widgets/native_primary_tab_bar.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/thread_directory_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        '$brightness at $scale fits narrow phones and shares forum surfaces',
        (tester) async {
          tester.view.physicalSize = const Size(320, 680);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final theme = brightness == Brightness.light
              ? AppTheme.light()
              : AppTheme.dark();
          final repository = ThreadDirectoryFixture(autoComplete: true);
          final opened = <String?>[];
          await _pump(
            tester,
            repository,
            theme: theme,
            scale: scale,
            page: UserThreadPage(
              initialType: UserThreadDirectoryType.replies,
              onOpenThread: (_, _, reply) => opened.add(reply?.postId),
            ),
          );
          final l10n = AppLocalizations.of(
            tester.element(find.byType(UserThreadPage)),
          );
          expect(find.text(l10n.profileMyThreadsTitle), findsOneWidget);
          expect(find.byType(NativePrimaryTabBar), findsOneWidget);
          expect(
            repository.requests.single.query.type,
            UserThreadDirectoryType.replies,
          );
          final card = find.byType(UserThreadCard);
          final material = tester.widget<Material>(
            find.descendant(of: card, matching: find.byType(Material)).first,
          );
          expect(material.color, theme.y300NativeContent.card);
          expect(material.elevation, 0);
          final title = tester.widget<Text>(
            find.text(threadSummary('100').title),
          );
          expect(
            title.style!.color,
            ThreadDetailNativePalette.resolve(theme).title,
          );
          final secondReply = find.byKey(const Key('my-thread-reply-502'));
          await tester.ensureVisible(secondReply);
          await tester.pumpAndSettle();
          await tester.tap(secondReply);
          expect(opened, ['502']);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'tap and swipe tabs preserve data while fetching only the visited tab',
    (tester) async {
      final repository = ThreadDirectoryFixture(autoComplete: true);
      await _pump(tester, repository);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(UserThreadPage)),
      );
      expect(repository.requests, hasLength(1));
      await tester.tap(find.text(l10n.profileMyRepliesTab));
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(2));
      expect(find.byKey(const Key('my-thread-reply-501')), findsOneWidget);
      await tester.drag(find.byType(TabBarView), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(2));
      expect(find.text('Source topic excerpt'), findsOneWidget);
      expect(find.byKey(const Key('my-thread-reply-501')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('short feeds remain pull-refreshable and reload page one', (
    tester,
  ) async {
    final repository = ThreadDirectoryFixture(autoComplete: true);
    await _pump(tester, repository);
    final refresh = find.byKey(const Key('my-thread-refresh-threads'));
    final scroll = tester.widget<CustomScrollView>(
      find.descendant(of: refresh, matching: find.byType(CustomScrollView)),
    );
    expect(scroll.physics, same(ForumPullToRefresh.scrollPhysics));
    await tester.drag(refresh, const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(2));
    expect(repository.requests.last.query.page, 1);
    expect(repository.requests.last.policy, CacheLoadPolicy.networkFirst);
  });

  testWidgets(
    'owner loss clears both personal tabs and suppresses pending reply navigation',
    (tester) async {
      final repository = ThreadDirectoryFixture(autoComplete: true);
      final locator = _PendingLocator();
      final container = ProviderContainer(
        overrides: [
          verifiedProfileOwnerProvider.overrideWithValue((
            uid: '101',
            revision: 0,
          )),
          userThreadDirectoryRepositoryProvider.overrideWithValue(repository),
          threadPostLocatorProvider.overrideWithValue(locator),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LocalizedTestApp(
            theme: AppTheme.light(),
            home: const UserThreadPage(
              initialType: UserThreadDirectoryType.replies,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-thread-reply-502')));
      await tester.pumpAndSettle();
      expect(locator.targets.single, (tid: '100', pid: '502'));
      expect(locator.sourceUri!.queryParameters['pid'], '502');
      container.updateOverrides([
        verifiedProfileOwnerProvider.overrideWithValue(null),
        userThreadDirectoryRepositoryProvider.overrideWithValue(repository),
        threadPostLocatorProvider.overrideWithValue(locator),
      ]);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(UserThreadPage)),
      );
      expect(find.text(l10n.profileThreadsLoginRequired), findsOneWidget);
      expect(find.byType(UserThreadCard), findsNothing);
      locator.pending.complete(
        const ApiSuccess(
          ThreadPostLocation(tid: '100', pid: '502', page: 3, url: ''),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ThreadDetailPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed loading shows localized retry without server diagnostics',
    (tester) async {
      final repository = ThreadDirectoryFixture();
      await _pump(tester, repository, settle: false);
      repository.fail(0, DataReadFailureKind.network);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(UserThreadPage)),
      );
      expect(find.text(l10n.commonNetworkError), findsOneWidget);
      expect(find.textContaining('raw server diagnostic'), findsNothing);
      await tester.tap(find.byKey(const Key('my-thread-retry')));
      repository.succeed(1, items: []);
      await tester.pumpAndSettle();
      expect(find.text(l10n.profileNoThreads), findsOneWidget);
      expect(repository.requests, hasLength(2));
    },
  );

  testWidgets('previews and avatars use the shared cache and stay bounded', (
    tester,
  ) async {
    final images = _NoDownloadImages();
    final item = UserThreadSummary(
      threadId: '100',
      title: 'Image topic',
      uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100'),
      authorName: 'Author',
      authorUserId: '101',
      avatarUrl: 'https://bbs.yamibo.com/avatar.jpg',
      images: [
        for (var i = 0; i < 4; i++) 'https://bbs.yamibo.com/image$i.jpg',
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(images),
          forumImageRefererProvider.overrideWithValue(
            'https://bbs.yamibo.com/',
          ),
        ],
        child: LocalizedTestApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(10),
              child: UserThreadCard(
                item: item,
                type: UserThreadDirectoryType.threads,
                onOpenThread: () {},
                onOpenReply: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ForumCachedAvatar), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(item.title)).dy,
      greaterThan(tester.getBottomLeft(find.byType(ForumCachedAvatar)).dy),
    );
    final previews = tester
        .widgetList<CachedLibraryImage>(find.byType(CachedLibraryImage))
        .where((image) => image.request?.role == ImageCacheRole.threadInline)
        .toList();
    expect(previews, hasLength(3));
    expect(images.keys, hasLength(4));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  ThreadDirectoryFixture repository, {
  UserThreadPage page = const UserThreadPage(),
  ThemeData? theme,
  double scale = 1,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedProfileOwnerProvider.overrideWithValue((
          uid: '101',
          revision: 0,
        )),
        userThreadDirectoryRepositoryProvider.overrideWithValue(repository),
      ],
      child: LocalizedTestApp(
        theme: theme ?? AppTheme.light(),
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
  if (settle) await tester.pumpAndSettle();
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

final class _NoDownloadImages implements ImageCacheService {
  final keys = <String>[];
  final pending = Completer<CachedImageResult?>();

  @override
  Future<CachedImageResult?> getCached(String cacheKey) {
    keys.add(cacheKey);
    return pending.future;
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) =>
      throw StateError('Image fixtures never download');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
