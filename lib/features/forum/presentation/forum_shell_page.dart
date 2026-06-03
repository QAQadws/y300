import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';

class ForumShellPage extends ConsumerWidget {
  const ForumShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncMode = ref.watch(forumShellModeControllerProvider);
    final mode = asyncMode.asData?.value ?? ForumShellMode.webview;

    return switch (mode) {
      ForumShellMode.native => const ForumHomePage(),
      ForumShellMode.webview => const ForumWebViewPage(),
    };
  }
}
