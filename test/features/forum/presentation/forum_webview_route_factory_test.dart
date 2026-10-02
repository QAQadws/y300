import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_account_guard.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_page.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  for (final target in ['101', '260328']) {
    for (final type in UserThreadDirectoryType.values) {
      for (final purpose in [
        ForumWebViewHostPurpose.browse,
        ForumWebViewHostPurpose.selfProfile,
      ]) {
        testWidgets(
          'initial $target $type URL builds the native directory for $purpose',
          (tester) async {
            var driverFactoryReads = 0;
            final container = ProviderContainer(
              overrides: [
                verifiedProfileOwnerProvider.overrideWithValue((
                  uid: '101',
                  revision: 0,
                )),
                forumWebViewDriverFactoryProvider.overrideWith((ref) {
                  driverFactoryReads++;
                  throw StateError(
                    'A native directory must not create a WebView',
                  );
                }),
              ],
            );
            addTearDown(container.dispose);
            final pageNumber = type == UserThreadDirectoryType.replies ? 4 : 1;
            final query =
                '${target == '101' ? '&view=me' : ''}'
                '${type == UserThreadDirectoryType.replies ? '&type=reply&page=4' : ''}';
            final route = container.read(forumWebViewRouteFactoryProvider)(
              ForumWebViewLaunchConfig(
                initialUri: Uri.parse(
                  'https://bbs.yamibo.com/home.php?mod=space&uid=$target&do=thread$query&mobile=2',
                ),
                purpose: purpose,
              ),
            );
            Widget? built;
            await tester.pumpWidget(
              LocalizedTestApp(
                home: Builder(
                  builder: (context) {
                    built = (route as MaterialPageRoute<Object?>).builder(
                      context,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            );

            expect(built, isA<UserThreadPage>());
            final page = built! as UserThreadPage;
            expect(page.userId, target);
            expect(page.initialType, type);
            expect(page.initialPage, pageNumber);
            expect(driverFactoryReads, 0);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('account-bound initial directory preserves its viewer guard', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        verifiedProfileOwnerProvider.overrideWithValue((
          uid: '101',
          revision: 0,
        )),
      ],
    );
    addTearDown(container.dispose);
    final route = container.read(forumWebViewRouteFactoryProvider)(
      ForumWebViewLaunchConfig(
        initialUri: Uri.parse(
          'https://bbs.yamibo.com/home.php?mod=space&uid=260328&do=thread&type=reply&page=4&mobile=2',
        ),
        expectedAccountId: '101',
      ),
    );
    Widget? built;
    UserThreadPage? inactivePage;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (context) {
            built = (route as MaterialPageRoute<Object?>).builder(context);
            if (built case final ForumWebViewAccountGuard guard) {
              inactivePage =
                  guard.builder(context, () => false) as UserThreadPage;
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(built, isA<ForumWebViewAccountGuard>());
    expect((built! as ForumWebViewAccountGuard).accountId, '101');
    expect(inactivePage?.userId, '260328');
    expect(inactivePage?.initialType, UserThreadDirectoryType.replies);
    expect(inactivePage?.initialPage, 4);
    expect(inactivePage?.isActive, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial directory URL preserves post edit WebView purpose', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        verifiedProfileOwnerProvider.overrideWithValue((
          uid: '101',
          revision: 0,
        )),
      ],
    );
    addTearDown(container.dispose);
    final route = container.read(forumWebViewRouteFactoryProvider)(
      ForumWebViewLaunchConfig(
        initialUri: Uri.parse(
          'https://bbs.yamibo.com/home.php?mod=space&uid=260328&do=thread&mobile=2',
        ),
        purpose: ForumWebViewHostPurpose.postEditFallback,
      ),
    );
    Widget? built;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (context) {
            built = (route as MaterialPageRoute<Object?>).builder(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(built, isA<ProviderScope>());
    expect(built, isNot(isA<UserThreadPage>()));
    expect(tester.takeException(), isNull);
  });

  for (final query in ['type=postcomment', 'view=all', 'view=we', 'uid=101']) {
    testWidgets('unsupported initial directory $query keeps a WebView route', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          verifiedProfileOwnerProvider.overrideWithValue((
            uid: '101',
            revision: 0,
          )),
        ],
      );
      addTearDown(container.dispose);
      final route = container.read(forumWebViewRouteFactoryProvider)(
        ForumWebViewLaunchConfig(
          initialUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=space&${query == 'uid=101' ? query : 'uid=260328&$query'}&do=thread&mobile=2',
          ),
        ),
      );
      Widget? built;
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Builder(
            builder: (context) {
              built = (route as MaterialPageRoute<Object?>).builder(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(built, isA<ProviderScope>());
      expect(built, isNot(isA<UserThreadPage>()));
      expect(tester.takeException(), isNull);
    });
  }
}
