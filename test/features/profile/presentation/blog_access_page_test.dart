import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' as riverpod_misc;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_navigation_fixture.dart';

void main() {
  for (final code in [
    'user_blog_password_required',
    'user_blog_private',
    'user_blog_unavailable',
  ]) {
    testWidgets(
      '$code has a safe explanation and a source-owned browser destination',
      (tester) async {
        final repository = _Details();
        final navigation = BlogNavigationFixture();
        final launches = <ForumWebViewLaunchConfig>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              blogAccountIdProvider.overrideWithValue('101'),
              userBlogDetailRepositoryProvider.overrideWithValue(repository),
              userBlogNavigationProvider.overrideWithValue(navigation),
              forumWebViewRouteFactoryProvider.overrideWithValue((config) {
                launches.add(config);
                return MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(),
                    body: const Text('browser fixture'),
                  ),
                );
              }),
            ],
            child: const LocalizedTestApp(
              home: ProfileBlogDetailPage(
                ownerUserId: '202',
                blogId: '11',
                commentId: '31',
              ),
            ),
          ),
        );
        repository.requests.single.complete(_failure(code));
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ProfileBlogDetailPage)),
        );
        final message = switch (code) {
          'user_blog_password_required' => l10n.profileBlogPasswordRequired,
          'user_blog_private' => l10n.profileBlogPrivate,
          _ => l10n.profileBlogUnavailable,
        };
        expect(find.text(message), findsOneWidget);
        expect(find.textContaining('server fixture payload'), findsNothing);
        await tester.tap(find.byKey(const Key('blog-read-open-web')));
        await tester.pumpAndSettle();
        expect(
          navigation.detailQuery,
          const UserBlogDetailQuery(
            ownerUserId: '202',
            blogId: '11',
            commentId: '31',
          ),
        );
        expect(launches.single.initialUri, navigation.uri);
        expect(launches.single.expectedAccountId, '101');
        expect(launches.single.popOnRootBack, isTrue);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(repository.requests, hasLength(1));
        expect(find.text(message), findsOneWidget);
      },
    );
  }

  testWidgets(
    'login boundaries offer the existing login flow without displaying payloads',
    (tester) async {
      final repository = _Details();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            blogAccountIdProvider.overrideWithValue(null),
            userBlogDetailRepositoryProvider.overrideWithValue(repository),
          ],
          child: const LocalizedTestApp(
            home: ProfileBlogDetailPage(ownerUserId: '202', blogId: '11'),
          ),
        ),
      );
      repository.requests.single.complete(
        const DataReadFailure(
          kind: DataReadFailureKind.unauthorized,
          code: 'user_blog_login_required',
          diagnosticMessage: 'server fixture payload',
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ProfileBlogDetailPage)),
      );
      expect(find.text(l10n.threadLoginRequired), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, l10n.authLoginTitle),
        findsOneWidget,
      );
      expect(find.textContaining('server fixture payload'), findsNothing);
    },
  );

  testWidgets(
    'known entry titles and late reads cannot cross an account switch',
    (tester) async {
      final repository = _Details();
      List<riverpod_misc.Override> overrides(String actor) => [
        blogAccountIdProvider.overrideWithValue(actor),
        userBlogDetailRepositoryProvider.overrideWithValue(repository),
      ];
      final container = ProviderContainer(overrides: overrides('101'));
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const LocalizedTestApp(
            home: ProfileBlogDetailPage(
              ownerUserId: '202',
              blogId: '11',
              initialTitle: 'private entry title',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('private entry title'), findsOneWidget);
      container.updateOverrides(overrides('303'));
      await tester.pump();
      await tester.pump();
      expect(find.text('private entry title'), findsNothing);
      repository.requests[0].complete(
        DataReadSuccess(
          data: const UserBlogDetailData(
            ownerUserId: '202',
            blogId: '11',
            title: 'late private title',
            bodyHtml: '<p>private body</p>',
            comments: [],
          ),
          capabilities: _capabilities,
          metadata: const DataReadMetadata.network(),
        ),
      );
      repository.requests[1].complete(_failure('user_blog_private'));
      await tester.pumpAndSettle();
      expect(find.text('late private title'), findsNothing);
      container.updateOverrides(overrides('101'));
      await tester.pump();
      await tester.pump();
      expect(find.text('private entry title'), findsNothing);
      repository.requests[2].complete(_failure('user_blog_private'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

final _capabilities = UserBlogDetailReadCapabilities(
  values: DataCapabilitySet.supported(UserBlogDetailCapability.values),
);
typedef _Read =
    DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>;
_Read _failure(String code) => DataReadFailure(
  kind: DataReadFailureKind.business,
  code: code,
  diagnosticMessage: 'server fixture payload',
);

class _Details implements UserBlogDetailRepository {
  final requests = <Completer<_Read>>[];
  @override
  UserBlogDetailSourceCapabilities get capabilities =>
      UserBlogDetailSourceCapabilities(values: _capabilities.values);
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
