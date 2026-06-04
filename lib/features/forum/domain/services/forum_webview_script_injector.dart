import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_visual_policy_models.dart';

final forumWebViewScriptInjectorProvider = Provider<ForumWebViewScriptInjector>((
  ref,
) {
  return const DefaultForumWebViewScriptInjector();
});

abstract class ForumWebViewScriptInjector {
  String cleanupScriptForPolicy(ForumWebViewVisualPolicy visualPolicy);

  Future<void> cleanChrome(
    ForumWebViewScriptTarget target, {
    required ForumWebViewVisualPolicy visualPolicy,
  });
}

abstract class ForumWebViewScriptTarget {
  Future<void> runJavaScript(String script);
}

class DefaultForumWebViewScriptInjector implements ForumWebViewScriptInjector {
  const DefaultForumWebViewScriptInjector();

  static const String _styleElementId = 'y300-forum-webview-late-style';

  @override
  String cleanupScriptForPolicy(ForumWebViewVisualPolicy visualPolicy) {
    final css = _buildCss(visualPolicy);
    return '''
(() => {
  const styleId = ${jsonEncode(_styleElementId)};
  const css = ${jsonEncode(css)};
  const removedSelectors = ${jsonEncode(visualPolicy.lateRemovedSelectors.toList())};
  const root = document.head || document.documentElement;
  if (root) {
    let style = document.getElementById(styleId);
    if (!style) {
      style = document.createElement('style');
      style.id = styleId;
      style.type = 'text/css';
      root.appendChild(style);
    }
    style.textContent = css;
  }
  removedSelectors.forEach((selector) => {
    document.querySelectorAll(selector).forEach((node) => node.remove());
  });
})();
''';
  }

  @override
  Future<void> cleanChrome(
    ForumWebViewScriptTarget target, {
    required ForumWebViewVisualPolicy visualPolicy,
  }) {
    return target.runJavaScript(cleanupScriptForPolicy(visualPolicy));
  }

  String _buildCss(ForumWebViewVisualPolicy visualPolicy) {
    final blocks = <String>[];
    if (visualPolicy.earlyHiddenSelectors.isNotEmpty) {
      blocks.add(
        '${visualPolicy.earlyHiddenSelectors.join(', ')} { display: none !important; }',
      );
    }
    if (visualPolicy.disableHorizontalOverflow) {
      blocks.add(
        'html, body { overflow-x: hidden !important; overscroll-behavior-x: none !important; }',
      );
    }
    final extraCss = visualPolicy.extraCss.trim();
    if (extraCss.isNotEmpty) {
      blocks.add(extraCss);
    }
    return blocks.join('\n');
  }
}
