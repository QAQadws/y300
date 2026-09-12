import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_account_guard.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets(
    'does not construct a browser until the expected account resolves',
    (tester) async {
      final controller = _Session();
      var builds = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionControllerProvider.overrideWith(() => controller),
          ],
          child: LocalizedTestApp(
            home: ForumWebViewAccountGuard(
              accountId: '101',
              builder: (_) {
                builds++;
                return const Text('private browser');
              },
            ),
          ),
        ),
      );
      expect(builds, 0);
      controller.initial.complete(_identity('101'));
      await tester.pumpAndSettle();
      expect(find.text('private browser'), findsOneWidget);
      expect(builds, 1);
    },
  );

  for (final next in ['202', null, 'loggingOut']) {
    testWidgets(
      '$next disposes the old browser and switching back cannot revive it',
      (tester) async {
        final controller = _Session()..initial.complete(_identity('101'));
        var disposed = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authSessionControllerProvider.overrideWith(() => controller),
            ],
            child: LocalizedTestApp(
              home: ForumWebViewAccountGuard(
                accountId: '101',
                builder: (_) => _Browser(onDispose: () => disposed++),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(tester.element(find.byType(_Browser)));
        controller.change(next);
        await tester.pumpAndSettle();
        expect(disposed, 1);
        expect(find.byType(_Browser), findsNothing);
        expect(find.text(l10n.forumWebViewAccountChanged), findsOneWidget);
        controller.change('101');
        await tester.pumpAndSettle();
        expect(find.byType(_Browser), findsNothing);
        expect(disposed, 1);
      },
    );
  }

  testWidgets(
    'session refresh retains the known actor until a new identity arrives',
    (tester) async {
      final controller = _Session()..initial.complete(_identity('101'));
      var disposed = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionControllerProvider.overrideWith(() => controller),
          ],
          child: LocalizedTestApp(
            home: ForumWebViewAccountGuard(
              accountId: '101',
              builder: (_) => _Browser(onDispose: () => disposed++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.change('refresh');
      await tester.pump();
      expect(disposed, 0);
      expect(find.byType(_Browser), findsOneWidget);
      controller.change('202');
      await tester.pumpAndSettle();
      expect(disposed, 1);
      expect(find.byType(_Browser), findsNothing);
    },
  );

  testWidgets('a wrong initial actor never opens the form', (tester) async {
    final controller = _Session()..initial.complete(_identity('202'));
    var builds = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionControllerProvider.overrideWith(() => controller),
        ],
        child: LocalizedTestApp(
          home: ForumWebViewAccountGuard(
            accountId: '101',
            builder: (_) {
              builds++;
              return const Text('private browser');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(builds, 0);
  });
}

class _Session extends AuthSessionController {
  final initial = Completer<AuthSessionViewState>();
  @override
  Future<AuthSessionViewState> build() => initial.future;
  void change(String? user) {
    state = user == 'refresh'
        ? const AsyncLoading()
        : AsyncData(
            user == null
                ? const AuthSessionViewState.signedOut()
                : _identity(
                    user == 'loggingOut' ? '101' : user,
                    loggingOut: user == 'loggingOut',
                  ),
          );
  }
}

AuthSessionViewState _identity(String user, {bool loggingOut = false}) =>
    AuthSessionViewState(
      isLoggedIn: true,
      uid: user,
      username: 'fixture',
      isLoggingOut: loggingOut,
    );

class _Browser extends StatefulWidget {
  const _Browser({required this.onDispose});
  final VoidCallback onDispose;
  @override
  State<_Browser> createState() => _BrowserState();
}

class _BrowserState extends State<_Browser> {
  @override
  Widget build(BuildContext context) => const Text('private browser');
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
