import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';

class ForumShellPage extends ConsumerWidget {
  const ForumShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncMode = ref.watch(forumShellModeControllerProvider);
    final mode = asyncMode.asData?.value ?? ForumShellMode.webview;

    return switch (mode) {
      ForumShellMode.native => const ForumHomePage(),
      ForumShellMode.webview => const _ForumWebViewPlaceholderPage(),
    };
  }
}

class _ForumWebViewPlaceholderPage extends StatelessWidget {
  const _ForumWebViewPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('forum-shell-webview-placeholder'),
      appBar: AppBar(title: const Text('百合会论坛')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'WebView 模式开发中，后续阶段接入百合会移动站',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
