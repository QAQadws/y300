import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/forum/presentation/widgets/forum_bootstrap_placeholder.dart';

class ForumWebViewBootstrapPlaceholder extends StatelessWidget {
  const ForumWebViewBootstrapPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const ForumBootstrapPlaceholder(
      listKey: Key('forum-webview-bootstrap-placeholder-list'),
      keyPrefix: 'forum-webview-placeholder',
    );
  }
}

Widget forumWebViewBootstrapPlaceholderPreviewShell(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: SafeArea(child: child),
    ),
  );
}

@Preview(
  name: 'Forum webview home placeholder',
  group: 'Forum/WebView',
  size: Size(500, 852),
  wrapper: forumWebViewBootstrapPlaceholderPreviewShell,
)
Widget forumWebViewBootstrapPlaceholderPreview() {
  return const ForumWebViewBootstrapPlaceholder();
}

@Preview(
  name: 'Forum webview section header',
  group: 'Forum/WebView',
  size: Size(393, 120),
  wrapper: forumWebViewBootstrapPlaceholderPreviewShell,
)
Widget forumWebViewSectionHeaderPreview() {
  return const Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    child: ForumBootstrapPlaceholder(
      keyPrefix: 'forum-webview-placeholder-preview',
    ),
  );
}

@Preview(
  name: 'Forum webview list rows',
  group: 'Forum/WebView',
  size: Size(393, 180),
  wrapper: forumWebViewBootstrapPlaceholderPreviewShell,
)
Widget forumWebViewListRowsPreview() {
  return const Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    child: SizedBox(height: 160, child: ForumBootstrapPlaceholder()),
  );
}

@Preview(
  name: 'Forum webview section',
  group: 'Forum/WebView',
  size: Size(393, 320),
  wrapper: forumWebViewBootstrapPlaceholderPreviewShell,
)
Widget forumWebViewSectionPreview() {
  return const Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    child: SizedBox(height: 300, child: ForumBootstrapPlaceholder()),
  );
}

@Preview(
  name: 'Forum webview placeholder block',
  group: 'Forum/WebView',
  size: Size(220, 120),
  wrapper: forumWebViewBootstrapPlaceholderPreviewShell,
)
Widget forumWebViewPlaceholderBlockPreview() {
  return Builder(
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const SizedBox(
            width: 120,
            height: 16,
          ),
        ),
      );
    },
  );
}
