import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_detail_failure_feedback.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/profile/presentation/profile_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_navigation_fixture.dart';

void main() {
  for (final failure in [
    _failure('user_blog_private'),
    _failure('user_blog_password_required'),
    _failure('user_blog_unavailable'),
    _failure('user_blog_login_required', DataReadFailureKind.unauthorized),
    _failure('network', DataReadFailureKind.network),
    _failure('parse', DataReadFailureKind.parse),
  ]) {
    testWidgets('${failure.code} returns to the feed with a browser action', (
      tester,
    ) async {
      final host = _Host();
      await host.pump(tester);
      final entryL10n = AppLocalizations.of(
        tester.element(find.byType(ProfileBlogPage)),
      );
      await tester.tap(find.byKey(const Key('profile-blog-item-11')));
      await tester.pump();
      host.details.requests.single.complete(failure);
      // Inspect the return animation, not only its settled destination: the old
      // full-page error used to paint briefly before the route was dismissed.
      for (final elapsed in [
        Duration.zero,
        const Duration(milliseconds: 16),
        const Duration(milliseconds: 80),
      ]) {
        await tester.pump(elapsed);
        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(
          find.widgetWithText(FilledButton, entryL10n.commonRetry),
          findsNothing,
        );
        expect(
          find.widgetWithText(FilledButton, entryL10n.authLoginTitle),
          findsNothing,
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(ProfileBlogDetailPage), findsNothing);
      expect(find.byType(ProfileBlogPage), findsOneWidget);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ProfileBlogPage)),
      );
      expect(
        find.widgetWithText(
          SnackBar,
          ProfileTextResolver.blogReadError(l10n, failure),
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SnackBarAction, l10n.profileBlogOpenWeb),
        findsOneWidget,
      );
      expect(find.textContaining('raw server payload'), findsNothing);
      expect(host.launches, isEmpty);
      expect(host.directory.reads, 1);
      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();
      expect(host.launches.single.initialUri, host.navigation!.uri);
      expect(host.launches.single.expectedAccountId, '101');
      expect(host.launches.single.popOnRootBack, isTrue);
      host.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(host.details.requests, hasLength(1));
      expect(host.directory.reads, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in AppLocalizations.supportedLocales) {
    for (final hasBrowserAction in [true, false]) {
      testWidgets(
        '$locale private entry feedback expires with browser action=$hasBrowserAction',
        (tester) async {
          final host = _Host();
          if (!hasBrowserAction) host.navigation = null;
          await host.pump(tester, locale: locale);
          host.open();
          await tester.pump();
          host.details.requests.single.complete(_failure('user_blog_private'));
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(ProfileBlogPage)),
          );
          final feedback = find.widgetWithText(
            SnackBar,
            l10n.profileBlogPrivate,
          );
          expect(feedback, findsOneWidget);
          expect(l10n.profileBlogPrivate.endsWith('。'), isFalse);
          expect(
            find.byType(SnackBarAction),
            hasBrowserAction ? findsOneWidget : findsNothing,
          );
          await tester.pump(const Duration(seconds: 3));
          expect(feedback, findsOneWidget);
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsNothing);
          // Expiry must not report the same failed request again on a rebuild.
          host.switchAccount('303');
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsNothing);
          expect(host.launches, isEmpty);
          expect(host.details.requests, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('comment links keep their source-owned browser destination', (
    tester,
  ) async {
    final host = _Host();
    await host.pump(tester);
    host.open(commentId: '31', page: 3);
    await tester.pump();
    host.details.requests.single.complete(_failure('user_blog_private'));
    await tester.pumpAndSettle();
    expect(
      host.navigation!.detailQuery,
      const UserBlogDetailQuery(
        ownerUserId: '202',
        blogId: '11',
        commentId: '31',
        page: 3,
      ),
    );
    await tester.tap(find.byType(SnackBarAction));
    await tester.pumpAndSettle();
    expect(host.launches.single.initialUri, host.navigation!.uri);
  });

  testWidgets('a failed entry preserves the source feed scroll position', (
    tester,
  ) async {
    final host = _Host()..directory.itemCount = 25;
    await host.pump(tester);
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('profile-blog-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    final entry = find.byKey(const Key('profile-blog-item-30'));
    await tester.scrollUntilVisible(entry, 150, scrollable: scrollable);
    // ensureVisible changes the scroll offset before the next layout frame.
    await tester.pumpAndSettle();
    expect(entry.hitTestable(), findsOneWidget);
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offset, greaterThan(0));
    await tester.tap(entry);
    await tester.pump();
    expect(host.details.requests, hasLength(1));
    host.details.requests.single.complete(_failure('user_blog_private'));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);
    expect(host.directory.reads, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'no browser capability still reports failure without a dead action',
    (tester) async {
      final host = _Host()..navigation = null;
      await host.pump(tester);
      host.open();
      await tester.pump();
      host.details.requests.single.complete(_failure('user_blog_private'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileBlogDetailPage), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(SnackBarAction), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closed routes and cancelled reads never report an entry failure',
    (tester) async {
      final host = _Host();
      await host.pump(tester);
      host.open();
      await tester.pump();
      host.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      host.details.requests[0].complete(_failure('user_blog_private'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      host.open();
      await tester.pump();
      host.details.requests[1].complete(
        _failure('cancelled', DataReadFailureKind.cancelled),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a route covered before feedback waits until it is current', (
    tester,
  ) async {
    final host = _Host();
    await host.pump(tester);
    host.open();
    await tester.pump();
    host.details.requests.single.complete(_failure('user_blog_private'));
    WidgetsBinding.instance.addPostFrameCallback((_) => host.cover());
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('overlay fixture'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    host.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileBlogDetailPage), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account changes reject pending feedback and stale browser actions',
    (tester) async {
      final host = _Host();
      await host.pump(tester);
      host.open();
      await tester.pump();
      host.details.requests[0].complete(_failure('user_blog_private'));
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => host.switchAccount('303'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
      host.details.requests[1].complete(_failure('user_blog_private'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBarAction), findsOneWidget);
      host.switchAccount('101');
      await tester.pumpAndSettle();
      host.switchAccount('303');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();
      expect(host.launches, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failure during refresh keeps the previously opened detail', (
    tester,
  ) async {
    final host = _Host();
    await host.pump(tester);
    host.open();
    await tester.pump();
    host.details.requests[0].complete(
      DataReadSuccess(
        data: const UserBlogDetailData(
          ownerUserId: '202',
          blogId: '11',
          title: 'article',
          bodyHtml: '<p>retained body</p>',
          comments: [],
        ),
        capabilities: host.details.capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<BlogDetailFailureFeedback>(
          find.byType(BlogDetailFailureFeedback),
        )
        .controller;
    final refreshing = controller.refresh();
    host.details.requests[1].complete(
      _failure('network', DataReadFailureKind.network),
    );
    await refreshing;
    await tester.pumpAndSettle();
    expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
    expect(find.text('retained body', findRichText: true), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final family in AppThemeFamily.values) {
    for (final brightness in Brightness.values) {
      for (final largeText in [false, true]) {
        testWidgets(
          '$family $brightness largeText=$largeText keeps the browser action reachable',
          (tester) async {
            final host = _Host();
            tester.view.physicalSize = Size(largeText ? 300 : 390, 750);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await host.pump(
              tester,
              largeText: largeText,
              theme: AppTheme.build(family: family, brightness: brightness),
            );
            host.open();
            await tester.pump();
            host.details.requests.single.complete(
              _failure('user_blog_password_required'),
            );
            await tester.pumpAndSettle();
            expect(find.byType(SnackBarAction).hitTestable(), findsOneWidget);
            if (!largeText) {
              final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
              final content = tester.getRect(find.byWidget(snackBar.content));
              final action = tester.getRect(find.byType(SnackBarAction));
              expect(action.left, greaterThan(content.right));
              expect(
                action.center.dy,
                inInclusiveRange(content.top, content.bottom),
              );
            }
            expect(tester.takeException(), isNull);
            await tester.tap(find.byType(SnackBarAction));
            await tester.pumpAndSettle();
            expect(host.launches, hasLength(1));
          },
        );
      }
    }
  }
}

typedef _Read =
    DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>;
DataReadFailure<UserBlogDetailData, UserBlogDetailReadCapabilities> _failure(
  String code, [
  DataReadFailureKind kind = DataReadFailureKind.business,
]) => DataReadFailure(
  kind: kind,
  code: code,
  diagnosticMessage: 'raw server payload',
);

class _Host {
  final navigator = GlobalKey<NavigatorState>();
  final details = _Details();
  final directory = _Directory();
  final launches = <ForumWebViewLaunchConfig>[];
  BlogNavigationFixture? navigation = BlogNavigationFixture();
  late final ProviderContainer container;

  List<Override> overrides(String actor) => [
    blogAccountIdProvider.overrideWithValue(actor),
    userBlogDetailRepositoryProvider.overrideWithValue(details),
    userBlogDirectoryRepositoryProvider.overrideWithValue(directory),
    userBlogNavigationProvider.overrideWithValue(navigation),
    forumWebViewRouteFactoryProvider.overrideWithValue((config) {
      launches.add(config);
      return MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('browser fixture')),
      );
    }),
  ];

  Future<void> pump(
    WidgetTester tester, {
    bool largeText = false,
    ThemeData? theme,
    Locale locale = const Locale('zh'),
  }) async {
    container = ProviderContainer(overrides: overrides('101'));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          locale: locale,
          navigatorKey: navigator,
          theme: theme ?? AppTheme.light(),
          builder: largeText
              ? (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                )
              : null,
          home: const ProfileBlogPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void open({String? commentId, int page = 1}) => unawaited(
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => ProfileBlogDetailPage(
          ownerUserId: '202',
          blogId: '11',
          commentId: commentId,
          initialPage: page,
        ),
      ),
    ),
  );
  void cover() => unawaited(
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('overlay fixture')),
      ),
    ),
  );
  void switchAccount(String actor) =>
      container.updateOverrides(overrides(actor));
}

class _Details implements UserBlogDetailRepository {
  final requests = <Completer<_Read>>[];
  @override
  final capabilities = UserBlogDetailSourceCapabilities(
    values: DataCapabilitySet.supported(UserBlogDetailCapability.values),
  );
  @override
  Future<_Read> load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) {
    final request = Completer<_Read>();
    requests.add(request);
    return request.future;
  }
}

class _Directory implements UserBlogDirectoryRepository {
  int reads = 0;
  int itemCount = 1;
  @override
  final capabilities = UserBlogDirectorySourceCapabilities(
    values: DataCapabilitySet.supported(UserBlogDirectoryCapability.values),
    paginationPrecision: PaginationPrecision.exact,
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
    reads++;
    return DataReadSuccess(
      data: UserBlogDirectoryData(
        scope: query.scope,
        order: query.order,
        items: [
          for (var index = 0; index < itemCount; index++)
            UserBlogSummary(
              ownerUserId: '202',
              blogId: '${11 + index}',
              title: 'entry fixture',
            ),
        ],
        pagination: UserBlogPagination(currentPage: query.page),
      ),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}
