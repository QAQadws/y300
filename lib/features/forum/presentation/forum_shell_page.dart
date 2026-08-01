import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/forum/presentation/widgets/forum_bootstrap_placeholder.dart';

class ForumShellPage extends ConsumerWidget {
  const ForumShellPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncMode = ref.watch(forumShellModeControllerProvider);
    final session =
        ref.watch(authSessionControllerProvider).asData?.value ??
        const AuthSessionViewState.signedOut();
    final webViewScopeKey = ValueKey<String>(
      'forum-webview-${session.isLoggedIn}-${session.username}',
    );

    return asyncMode.when(
      loading: () => const _ForumShellLoadingView(),
      error: (_, _) => const _ForumShellLoadingView(),
      data: (mode) {
        return switch (mode) {
          ForumShellMode.native => ForumHomePage(isActive: isActive),
          ForumShellMode.webview => ProviderScope(
            key: webViewScopeKey,
            overrides: [
              forumWebViewDriverProvider.overrideWith((ref) {
                final factory = ref.watch(forumWebViewDriverFactoryProvider);
                return factory();
              }),
              forumWebViewControllerProvider.overrideWith(
                ForumWebViewController.new,
              ),
            ],
            child: const ForumWebViewPage(),
          ),
        };
      },
    );
  }
}

class _ForumShellLoadingView extends StatelessWidget {
  const _ForumShellLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: ForumBootstrapPlaceholder(
          listKey: Key('forum-shell-bootstrap-placeholder-list'),
          keyPrefix: 'forum-shell-bootstrap-placeholder',
        ),
      ),
    );
  }
}
