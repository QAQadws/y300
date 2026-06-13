import 'package:flutter/material.dart';
import 'package:y300/features/forum/presentation/webview/runtime/forum_webview_bootstrap_placeholder.dart';

class ForumWebViewLoadingMask extends StatelessWidget {
  const ForumWebViewLoadingMask({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        key: const Key('forum-webview-loading-mask'),
        child: const ForumWebViewBootstrapPlaceholder(),
      ),
    );
  }
}
