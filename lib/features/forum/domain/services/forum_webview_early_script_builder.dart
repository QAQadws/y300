import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_runtime_models.dart';
import 'package:y300/features/forum/domain/models/forum_webview_visual_policy_models.dart';

final forumWebViewEarlyScriptBuilderProvider =
    Provider<ForumWebViewEarlyScriptBuilder>((ref) {
      return const DefaultForumWebViewEarlyScriptBuilder();
    });

abstract class ForumWebViewEarlyScriptBuilder {
  List<ForumWebViewInitialUserScript> build({
    required ForumWebViewCapabilityProfile capabilityProfile,
    required ForumWebViewVisualPolicy visualPolicy,
  });
}

class DefaultForumWebViewEarlyScriptBuilder
    implements ForumWebViewEarlyScriptBuilder {
  const DefaultForumWebViewEarlyScriptBuilder();

  static const String _styleElementId = 'y300-forum-webview-early-style';

  @override
  List<ForumWebViewInitialUserScript> build({
    required ForumWebViewCapabilityProfile capabilityProfile,
    required ForumWebViewVisualPolicy visualPolicy,
  }) {
    if (capabilityProfile.documentStartMode ==
        ForumWebViewDocumentStartMode.unavailable) {
      return const <ForumWebViewInitialUserScript>[];
    }

    return <ForumWebViewInitialUserScript>[
      ForumWebViewInitialUserScript(
        source: _buildEarlyScript(visualPolicy),
        injectionTime:
            ForumWebViewInitialUserScriptInjectionTime.documentStart,
      ),
    ];
  }

  String _buildEarlyScript(ForumWebViewVisualPolicy visualPolicy) {
    final css = _buildCss(visualPolicy);
    return '''
(() => {
  if (window.location.host !== 'bbs.yamibo.com') {
    return;
  }
  const styleId = ${jsonEncode(_styleElementId)};
  const css = ${jsonEncode(css)};
  const install = () => {
    if (document.getElementById(styleId)) {
      return;
    }
    const root = document.head || document.documentElement;
    if (!root) {
      return;
    }
    const style = document.createElement('style');
    style.id = styleId;
    style.type = 'text/css';
    style.textContent = css;
    root.appendChild(style);
  };
  install();
  if (!document.getElementById(styleId)) {
    document.addEventListener('readystatechange', install);
  }
})();
''';
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
