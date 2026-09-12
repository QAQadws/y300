import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_action_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_comment_fixture.dart';
import '../test_support/blog_operation_fixture.dart';

void main() {
  testWidgets(
    'publishing opens the verified article and defers the feed refresh',
    (tester) async {
      final directory = _FakeBlogDirectoryRepository();
      final details = _FakeBlogDetailRepository(title: 'Newly published');
      final operations = BlogOperationFixture(autoPrepare: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            blogAccountIdProvider.overrideWithValue('101'),
            userBlogDirectoryRepositoryProvider.overrideWithValue(directory),
            userBlogDetailRepositoryProvider.overrideWithValue(details),
            userBlogOperationsProvider.overrideWithValue(operations),
            forumImageRefererProvider.overrideWithValue(
              'https://example.test/',
            ),
          ],
          child: const LocalizedTestApp(home: ProfileBlogPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('blog-write')));
      await tester.pumpAndSettle();
      expect(find.byType(BlogEditorPage), findsOneWidget);
      expect(
        operations.editorPreparations.single.target.action,
        UserBlogAction.create,
      );
      await tester.enterText(
        find.byKey(const Key('blog-editor-subject')),
        'Newly published',
      );
      await tester.enterText(
        find.byKey(const Key('blog-editor-body')),
        'New body',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('blog-editor-submit')));
      await tester.pump();
      operations.saved();
      await tester.pumpAndSettle();
      final page = tester.widget<ProfileBlogDetailPage>(
        find.byType(ProfileBlogDetailPage),
      );
      expect(page.blogId, '12');
      expect(page.ownerUserId, '101');
      expect(page.initialTitle, 'Newly published');
      expect(details.queries.single.blogId, '12');
      expect(directory.queries, hasLength(1));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(directory.queries, hasLength(2));
      expect(directory.policies.last, CacheLoadPolicy.networkFirst);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fromDetail in [false, true]) {
    testWidgets(
      'editing from ${fromDetail ? 'detail' : 'list'} refreshes existing views after saving',
      (tester) async {
        final directory = _FakeBlogDirectoryRepository(
          blogActions: {UserBlogAction.edit},
        );
        final details = _FakeBlogDetailRepository(
          blogActions: {UserBlogAction.edit},
        );
        final operations = BlogOperationFixture(autoPrepare: true);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              blogAccountIdProvider.overrideWithValue('257582'),
              userBlogDirectoryRepositoryProvider.overrideWithValue(directory),
              userBlogDetailRepositoryProvider.overrideWithValue(details),
              userBlogOperationsProvider.overrideWithValue(operations),
              forumImageRefererProvider.overrideWithValue(
                'https://example.test/',
              ),
            ],
            child: const LocalizedTestApp(home: ProfileBlogPage()),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ProfileBlogPage)),
        );
        if (fromDetail) {
          await tester.tap(find.byKey(const Key('profile-blog-item-117558')));
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.byKey(
            Key(
              fromDetail ? 'blog-detail-actions' : 'blog-list-actions-117558',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.profileBlogEdit));
        await tester.pumpAndSettle();
        expect(find.byType(BlogEditorPage), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('blog-editor-subject')),
          'Changed title',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('blog-editor-submit')));
        await tester.pump();
        details.title = 'Changed title';
        operations.saved();
        await tester.pumpAndSettle();
        if (fromDetail) {
          expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
          expect(details.queries, hasLength(2));
          expect(find.text('Changed title'), findsWidgets);
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
        }
        expect(find.byType(ProfileBlogPage), findsOneWidget);
        expect(directory.queries, hasLength(2));
        expect(
          operations.editorSubmissions.single.input.subject,
          'Changed title',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final fromDetail in [false, true]) {
    for (final action in blogManagementActions) {
      for (final applied in [false, true]) {
        testWidgets(
          '$action from ${fromDetail ? 'detail' : 'list'} updates only when applied=$applied',
          (tester) async {
            final directory = _FakeBlogDirectoryRepository(
              blogActions: {action},
            );
            final details = _FakeBlogDetailRepository(blogActions: {action});
            final operations = BlogOperationFixture(autoPrepare: true);
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  blogAccountIdProvider.overrideWithValue('257582'),
                  userBlogDirectoryRepositoryProvider.overrideWithValue(
                    directory,
                  ),
                  userBlogDetailRepositoryProvider.overrideWithValue(details),
                  userBlogOperationsProvider.overrideWithValue(operations),
                  forumImageRefererProvider.overrideWithValue(
                    'https://example.test/',
                  ),
                ],
                child: const LocalizedTestApp(home: ProfileBlogPage()),
              ),
            );
            await tester.pumpAndSettle();
            final l10n = AppLocalizations.of(
              tester.element(find.byType(ProfileBlogPage)),
            );
            if (fromDetail) {
              await tester.tap(
                find.byKey(const Key('profile-blog-item-117558')),
              );
              await tester.pumpAndSettle();
            }
            await tester.tap(
              find.byKey(
                Key(
                  fromDetail
                      ? 'blog-detail-actions'
                      : 'blog-list-actions-117558',
                ),
              ),
            );
            await tester.pumpAndSettle();
            for (final other in blogManagementActions.where(
              (other) => other != action,
            )) {
              expect(find.text(blogActionLabel(l10n, other)), findsNothing);
            }
            await tester.tap(find.text(blogActionLabel(l10n, action)));
            await tester.pumpAndSettle();
            expect(find.byType(BlogActionPage), findsOneWidget);
            expect(operations.preparations.single.target.blogId, '117558');
            expect(operations.preparations.single.target.ownerUserId, '257582');
            expect(operations.submissions, isEmpty);
            await tester.tap(find.byKey(const Key('blog-action-submit')));
            await tester.pump();
            expect(directory.queries, hasLength(1));
            expect(details.queries, hasLength(fromDetail ? 1 : 0));
            if (applied) {
              directory.removed = action == UserBlogAction.delete;
              operations.applied();
            } else {
              operations.submissions.last.result.complete(
                const DataCommandOutcomeUnknown(blogActionWriteFailure),
              );
            }
            await tester.pumpAndSettle();
            if (!applied) {
              expect(find.byType(BlogActionPage), findsOneWidget);
              expect(find.byKey(const Key('blog-action-retry')), findsNothing);
              await tester.tap(find.byType(BackButton));
              await tester.pumpAndSettle();
            }
            if (fromDetail && !(applied && action == UserBlogAction.delete)) {
              expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
              expect(details.queries, hasLength(applied ? 2 : 1));
              await tester.tap(find.byType(BackButton));
              await tester.pumpAndSettle();
            }
            expect(find.byType(ProfileBlogPage), findsOneWidget);
            expect(directory.queries, hasLength(applied ? 2 : 1));
            if (applied) {
              expect(directory.policies.last, CacheLoadPolicy.networkFirst);
            }
            if (applied && action == UserBlogAction.delete) {
              expect(
                find.byKey(const Key('profile-blog-item-117558')),
                findsNothing,
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final action in UserBlogCommentAction.values) {
    for (final applied in [true, false]) {
      testWidgets('$action refreshes comment data only when applied=$applied', (
        tester,
      ) async {
        final details = _FakeBlogDetailRepository(commentActions: {action});
        final comments = BlogCommentFixture(autoPrepare: true);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              blogAccountIdProvider.overrideWithValue('101'),
              userBlogDetailRepositoryProvider.overrideWithValue(details),
              userBlogCommentServiceProvider.overrideWithValue(comments),
              forumImageRefererProvider.overrideWithValue(
                'https://bbs.yamibo.com/',
              ),
            ],
            child: const LocalizedTestApp(
              home: ProfileBlogDetailPage(ownerUserId: '202', blogId: '11'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ProfileBlogDetailPage)),
        );
        if (action == UserBlogCommentAction.add) {
          final add = find.byKey(const Key('profile-blog-comment-button'));
          await tester.scrollUntilVisible(
            add,
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(add);
        } else {
          final menu = find.byKey(const Key('blog-comment-actions-646846'));
          await tester.scrollUntilVisible(
            menu,
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(menu);
          await tester.pumpAndSettle();
          for (final other in UserBlogCommentAction.values) {
            if (other != action && other != UserBlogCommentAction.add) {
              expect(
                find.text(blogCommentActionLabel(l10n, other)),
                findsNothing,
              );
            }
          }
          await tester.tap(find.text(blogCommentActionLabel(l10n, action)));
        }
        await tester.pumpAndSettle();
        expect(find.byType(BlogCommentPage), findsOneWidget);
        expect(
          comments.preparations.single.target,
          UserBlogCommentTarget(
            actorUserId: '101',
            ownerUserId: '202',
            blogId: '11',
            action: action,
            commentId: action == UserBlogCommentAction.add ? null : '646846',
          ),
        );
        if (action != UserBlogCommentAction.delete) {
          await tester.enterText(find.byType(TextField), '实际输入内容');
        }
        await tester.pump();
        await tester.tap(find.byKey(const Key('blog-comment-submit')));
        await tester.pump();
        expect(details.queries, hasLength(1));
        if (applied) {
          comments.applied();
          await tester.pumpAndSettle();
          expect(details.queries, hasLength(2));
          expect(details.policies.last, CacheLoadPolicy.networkFirst);
          expect(
            details.queries.last.lastCommentPage,
            action == UserBlogCommentAction.add ||
                action == UserBlogCommentAction.reply,
          );
        } else {
          comments.submissions.single.result.complete(
            const DataCommandOutcomeUnknown(blogCommentWriteFailure),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('blog-comment-leave')));
          await tester.pumpAndSettle();
          expect(details.queries, hasLength(1));
          // An inconclusive write leaves the article untouched, but the
          // user must still be able to check it by pulling a short page.
          await tester.drag(
            find.byKey(const Key('profile-blog-detail')),
            const Offset(0, 400),
          );
          await tester.pumpAndSettle();
          expect(details.queries, hasLength(2));
          expect(details.policies.last, CacheLoadPolicy.networkFirst);
        }
        expect(find.byType(BlogCommentPage), findsNothing);
        expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('tabs remain usable while the first request is pending', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repository = _FakeBlogDirectoryRepository(gate: gate);
    await _pumpBlogPage(
      tester,
      directoryRepository: repository,
      detailRepository: _FakeBlogDetailRepository(),
      settle: false,
    );
    await tester.pump();
    expect(find.byKey(const Key('profile-blog-view-tabs')), findsOneWidget);
    await tester.tap(find.text('我的日志'));
    await tester.pump();
    expect(repository.queries.map((q) => q.scope), [
      UserBlogFeedScope.public,
      UserBlogFeedScope.self,
    ]);
    expect(repository.cancellations.first!.isCancelled, isTrue);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('一种体验'), findsNothing);
    expect(find.text('还没有相关的日志'), findsOneWidget);
  });

  testWidgets('returning from a pending article cancels its read', (
    tester,
  ) async {
    final gate = Completer<void>();
    final details = _FakeBlogDetailRepository(gate: gate);
    await _pumpBlogPage(
      tester,
      directoryRepository: _FakeBlogDirectoryRepository(),
      detailRepository: details,
    );
    await tester.tap(find.text('一种体验'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ProfileBlogDetailPage),
        matching: find.text('一种体验'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(details.cancellations.single!.isCancelled, isTrue);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileBlogDetailPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the last scroll offset is restored independently for each tab', (
    tester,
  ) async {
    final repository = _FakeBlogDirectoryRepository(longList: true);
    await _pumpBlogPage(
      tester,
      directoryRepository: repository,
      detailRepository: _FakeBlogDetailRepository(),
    );
    final list = find.byKey(const Key('profile-blog-list'));
    await tester.drag(list, const Offset(0, -650));
    await tester.pumpAndSettle();
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    final before = offset();
    expect(before, greaterThan(400));
    await tester.tap(find.text('我的日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('随便看看'));
    await tester.pumpAndSettle();
    expect(offset(), closeTo(before, 1));
    expect(repository.queries, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'two routes with the same feed use separate controller instances',
    (tester) async {
      final repository = _FakeBlogDirectoryRepository();
      await _pumpBlogPage(
        tester,
        directoryRepository: repository,
        detailRepository: _FakeBlogDetailRepository(),
      );
      final context = tester.element(find.text('随便看看'));
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProfileBlogPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.queries, hasLength(2));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(repository.queries, hasLength(3));
      expect(find.text('一种体验'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ProfileBlogPage switches structured queries and opens detail', (
    tester,
  ) async {
    final directoryRepository = _FakeBlogDirectoryRepository();
    final detailRepository = _FakeBlogDetailRepository();
    await _pumpBlogPage(
      tester,
      directoryRepository: directoryRepository,
      detailRepository: detailRepository,
    );

    expect(find.byKey(const Key('profile-blog-list')), findsOneWidget);
    expect(find.byKey(const Key('profile-blog-view-tabs')), findsOneWidget);
    expect(find.text('随便看看'), findsOneWidget);
    expect(find.text('最新发表的日志'), findsOneWidget);
    expect(find.text('一种体验'), findsOneWidget);

    await tester.tap(find.text('推荐阅读的日志'));
    await tester.pumpAndSettle();

    expect(directoryRepository.queries.last.order, UserBlogOrder.recommended);
    expect(find.text('我们小区的公共交通极其不便利'), findsOneWidget);

    await tester.tap(find.text('我的日志'));
    await tester.pumpAndSettle();

    expect(directoryRepository.queries.last.scope, UserBlogFeedScope.self);
    expect(directoryRepository.queries.last.order, isNull);
    expect(find.text('还没有相关的日志'), findsOneWidget);

    await tester.tap(find.text('随便看看'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('推荐阅读的日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我们小区的公共交通极其不便利'));
    await tester.pumpAndSettle();

    expect(detailRepository.queries.single.ownerUserId, '257582');
    expect(detailRepository.queries.single.blogId, '117548');
    expect(find.byKey(const Key('profile-blog-detail')), findsOneWidget);
    expect(
      find.text('hsyhlj · 2026-6-18 00:25 · 浏览 39 · 评论 1'),
      findsOneWidget,
    );
    expect(_richTextContaining('一直对着电脑屏幕'), findsOneWidget);
    expect(find.text('日志评论'), findsOneWidget);
    expect(_richTextContaining('探险的感觉'), findsOneWidget);
  });

  testWidgets('next page constructs a page-only domain query', (tester) async {
    final repository = _FakeBlogDirectoryRepository();
    await _pumpBlogPage(
      tester,
      directoryRepository: repository,
      detailRepository: _FakeBlogDetailRepository(),
    );

    await tester.tap(find.byKey(const Key('profile-blog-next-page-button')));
    await tester.pumpAndSettle();

    expect(repository.queries.last.page, 2);
    expect(repository.queries.last.scope, UserBlogFeedScope.public);
    expect(repository.queries.last.order, UserBlogOrder.latest);
    expect(find.text('第二页日志'), findsOneWidget);
  });

  testWidgets('capabilities hide optional list and detail fields', (
    tester,
  ) async {
    final directoryCapabilities = _directoryCapabilities(
      supported: const <UserBlogDirectoryCapability>[
        UserBlogDirectoryCapability.stableFeedIdentity,
        UserBlogDirectoryCapability.orderedEntries,
        UserBlogDirectoryCapability.stableBlogIdentity,
        UserBlogDirectoryCapability.stableOwnerIdentity,
        UserBlogDirectoryCapability.title,
      ],
    );
    final detailCapabilities = _detailCapabilities(
      supported: const <UserBlogDetailCapability>[
        UserBlogDetailCapability.stableBlogIdentity,
        UserBlogDetailCapability.stableOwnerIdentity,
        UserBlogDetailCapability.title,
        UserBlogDetailCapability.bodyMarkup,
      ],
    );
    await _pumpBlogPage(
      tester,
      directoryRepository: _FakeBlogDirectoryRepository(
        capabilities: directoryCapabilities,
      ),
      detailRepository: _FakeBlogDetailRepository(
        capabilities: detailCapabilities,
      ),
    );

    expect(find.text('一种体验'), findsOneWidget);
    expect(find.text('抉择'), findsNothing);
    expect(find.text('2026-6-21 13:06'), findsNothing);
    expect(find.textContaining('作为女生'), findsNothing);

    await tester.tap(find.text('一种体验'));
    await tester.pumpAndSettle();

    expect(find.textContaining('浏览 39'), findsNothing);
    expect(find.text('日志评论'), findsNothing);
    expect(find.byKey(const Key('profile-blog-comment-button')), findsNothing);
  });

  testWidgets('refresh failure retains existing directory content', (
    tester,
  ) async {
    final repository = _FakeBlogDirectoryRepository(failAfterSuccess: true);
    await _pumpBlogPage(
      tester,
      directoryRepository: repository,
      detailRepository: _FakeBlogDetailRepository(),
    );
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();

    expect(find.text('一种体验'), findsOneWidget);
    expect(find.textContaining('网络连接失败'), findsOneWidget);
    expect(repository.policies, <CacheLoadPolicy>[
      CacheLoadPolicy.cacheFirst,
      CacheLoadPolicy.networkFirst,
    ]);
  });

  testWidgets('initial failure shows retry and then loads content', (
    tester,
  ) async {
    final repository = _FakeBlogDirectoryRepository(failFirst: true);
    await _pumpBlogPage(
      tester,
      directoryRepository: repository,
      detailRepository: _FakeBlogDetailRepository(),
      settle: false,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('网络连接失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('一种体验'), findsOneWidget);
  });

  testWidgets('ProfileBlogPage localizes chrome and preserves server titles', (
    tester,
  ) async {
    await _pumpBlogPage(
      tester,
      directoryRepository: _FakeBlogDirectoryRepository(),
      detailRepository: _FakeBlogDetailRepository(),
      locale: const Locale('zh', 'TW'),
    );

    expect(find.text('隨便看看'), findsOneWidget);
    expect(find.text('最新發表的日誌'), findsOneWidget);
    expect(find.text('一种体验'), findsOneWidget);
  });

  testWidgets('blog layout remains usable at 300dp with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          blogAccountIdProvider.overrideWithValue('101'),
          userBlogDirectoryRepositoryProvider.overrideWithValue(
            _FakeBlogDirectoryRepository(),
          ),
          userBlogDetailRepositoryProvider.overrideWithValue(
            _FakeBlogDetailRepository(),
          ),
          forumImageRefererProvider.overrideWithValue(
            'https://bbs.yamibo.com/',
          ),
        ],
        child: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: LocalizedTestApp(home: ProfileBlogPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('profile-blog-list')), findsOneWidget);
  });
}

Future<void> _pumpBlogPage(
  WidgetTester tester, {
  required UserBlogDirectoryRepository directoryRepository,
  required UserBlogDetailRepository detailRepository,
  Locale locale = const Locale('zh'),
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        blogAccountIdProvider.overrideWithValue('101'),
        userBlogDirectoryRepositoryProvider.overrideWithValue(
          directoryRepository,
        ),
        userBlogDetailRepositoryProvider.overrideWithValue(detailRepository),
        forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      ],
      child: LocalizedTestApp(locale: locale, home: const ProfileBlogPage()),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
}

UserBlogDirectoryReadCapabilities _directoryCapabilities({
  Iterable<UserBlogDirectoryCapability> supported =
      UserBlogDirectoryCapability.values,
}) {
  return UserBlogDirectoryReadCapabilities(
    values: DataCapabilitySet<UserBlogDirectoryCapability>.from(
      supported: supported,
      unsupported: UserBlogDirectoryCapability.values.where(
        (value) => !supported.contains(value),
      ),
    ),
    paginationPrecision:
        supported.contains(UserBlogDirectoryCapability.totalPageCount)
        ? PaginationPrecision.exact
        : PaginationPrecision.unknown,
  );
}

UserBlogDetailReadCapabilities _detailCapabilities({
  Iterable<UserBlogDetailCapability> supported =
      UserBlogDetailCapability.values,
}) {
  return UserBlogDetailReadCapabilities(
    values: DataCapabilitySet<UserBlogDetailCapability>.from(
      supported: supported,
      unsupported: UserBlogDetailCapability.values.where(
        (value) => !supported.contains(value),
      ),
    ),
  );
}

class _FakeBlogDirectoryRepository implements UserBlogDirectoryRepository {
  _FakeBlogDirectoryRepository({
    UserBlogDirectoryReadCapabilities? capabilities,
    this.failAfterSuccess = false,
    this.failFirst = false,
    this.gate,
    this.longList = false,
    this.blogActions = const {},
  }) : readCapabilities = capabilities ?? _directoryCapabilities();

  final UserBlogDirectoryReadCapabilities readCapabilities;
  final bool failAfterSuccess;
  final bool failFirst;
  final Completer<void>? gate;
  final bool longList;
  final Set<UserBlogAction> blogActions;
  bool removed = false;
  final cancellations = <ForumRequestCancellation?>[];
  final List<UserBlogDirectoryQuery> queries = <UserBlogDirectoryQuery>[];
  final List<CacheLoadPolicy> policies = <CacheLoadPolicy>[];

  @override
  UserBlogDirectorySourceCapabilities get capabilities =>
      UserBlogDirectorySourceCapabilities(
        values: readCapabilities.values,
        paginationPrecision: readCapabilities.paginationPrecision,
      );

  @override
  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  load(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    queries.add(query);
    policies.add(cachePolicy);
    cancellations.add(cancellation);
    await gate?.future;
    if ((failFirst && queries.length == 1) ||
        (failAfterSuccess && queries.length > 1)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.network,
        diagnosticMessage: 'network failure',
      );
    }
    return DataReadSuccess(
      data: _directoryData(query),
      capabilities: readCapabilities,
      metadata: const DataReadMetadata.network(),
    );
  }

  UserBlogDirectoryData _directoryData(UserBlogDirectoryQuery query) {
    if (query.scope != UserBlogFeedScope.public) {
      return UserBlogDirectoryData(
        scope: query.scope,
        order: null,
        items: const <UserBlogSummary>[],
        pagination: UserBlogPagination(currentPage: query.page),
      );
    }
    if (longList) {
      return UserBlogDirectoryData(
        scope: query.scope,
        order: query.order,
        items: [
          for (var i = 0; i < 30; i++)
            UserBlogSummary(
              blogId: '${i + 1}',
              ownerUserId: '101',
              title: 'Entry $i',
              excerpt:
                  'A longer journal excerpt for checking retained scroll position.',
            ),
        ],
        pagination: const UserBlogPagination(currentPage: 1, hasNext: false),
      );
    }
    if (query.page == 2) {
      return const UserBlogDirectoryData(
        scope: UserBlogFeedScope.public,
        order: UserBlogOrder.latest,
        items: <UserBlogSummary>[
          UserBlogSummary(
            blogId: '117600',
            ownerUserId: '257582',
            title: '第二页日志',
          ),
        ],
        pagination: UserBlogPagination(
          currentPage: 2,
          totalPages: 2,
          hasPrevious: true,
          hasNext: false,
        ),
      );
    }
    final recommended = query.order == UserBlogOrder.recommended;
    return UserBlogDirectoryData(
      scope: UserBlogFeedScope.public,
      order: query.order ?? UserBlogOrder.latest,
      items: <UserBlogSummary>[
        if (!removed)
          UserBlogSummary(
            blogId: recommended ? '117548' : '117558',
            ownerUserId: '257582',
            title: recommended ? '我们小区的公共交通极其不便利' : '一种体验',
            authorName: recommended ? 'hsyhlj' : '抉择',
            excerpt: '作为女生，见血是常有的事',
            publishedAtText: '2026-6-21 13:06',
            actions: blogActions,
          ),
      ],
      pagination: const UserBlogPagination(
        currentPage: 1,
        totalPages: 2,
        hasPrevious: false,
        hasNext: true,
      ),
    );
  }
}

class _FakeBlogDetailRepository implements UserBlogDetailRepository {
  _FakeBlogDetailRepository({
    UserBlogDetailReadCapabilities? capabilities,
    this.gate,
    this.commentActions = const {},
    this.blogActions = const {},
    this.title = '我们小区的公共交通极其不便利',
  }) : readCapabilities = capabilities ?? _detailCapabilities();

  final UserBlogDetailReadCapabilities readCapabilities;
  final Set<UserBlogCommentAction> commentActions;
  final Set<UserBlogAction> blogActions;
  String title;
  final policies = <CacheLoadPolicy>[];
  final Completer<void>? gate;
  final cancellations = <ForumRequestCancellation?>[];
  final List<UserBlogDetailQuery> queries = <UserBlogDetailQuery>[];

  @override
  UserBlogDetailSourceCapabilities get capabilities =>
      UserBlogDetailSourceCapabilities(values: readCapabilities.values);

  @override
  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    queries.add(query);
    policies.add(cachePolicy);
    cancellations.add(cancellation);
    await gate?.future;
    return DataReadSuccess(
      data: UserBlogDetailData(
        blogId: query.blogId,
        ownerUserId: query.ownerUserId,
        title: title,
        bodyHtml: '<p>一直对着电脑屏幕</p>',
        authorName: 'hsyhlj',
        publishedAtText: '2026-6-18 00:25',
        viewCount: 39,
        commentCount: 1,
        commentsOpen: true,
        actions: blogActions,
        comments: <UserBlogComment>[
          UserBlogComment(
            commentId: '646846',
            authorName: 'thessky',
            bodyHtml: '<p>探险的感觉</p>',
            publishedAtText: '2026-6-18 01:00',
            actions: commentActions,
          ),
        ],
      ),
      capabilities: readCapabilities,
      metadata: const DataReadMetadata.network(),
    );
  }
}

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate((widget) {
    return widget is RichText && widget.text.toPlainText().contains(text);
  });
}
