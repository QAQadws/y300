import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/models/forum_webview_visual_policy_models.dart';

final forumWebViewVisualPolicyResolverProvider =
    Provider<ForumWebViewVisualPolicyResolver>((ref) {
      return const DefaultForumWebViewVisualPolicyResolver();
    });

abstract class ForumWebViewVisualPolicyResolver {
  ForumWebViewVisualPolicy resolve(ForumWebViewPageKind pageKind);
}

class DefaultForumWebViewVisualPolicyResolver
    implements ForumWebViewVisualPolicyResolver {
  const DefaultForumWebViewVisualPolicyResolver();

  static const Set<String> _baselineSelectors = <String>{
    '#header-padding',
    '.header.cl',
    '.footer.mt10.cl',
    '.foot.flex-box',
  };
  static const Set<String> _pwaLateOnlySelectors = <String>{
    '.foot_height',
    '.foot-pwa',
  };
  static const Set<String> _threadDetailExtraSelectors = <String>{
    '.foot.foot_reply.flex-box.cl',
    '.foot_height_view',
  };
  static const String _sharedExtraCss =
      'html, body { margin: 0 !important; padding: 0 !important; background: transparent !important; }\n'
      'img, video, svg, canvas, iframe { max-width: 100% !important; height: auto !important; }';

  static final ForumWebViewVisualPolicy _homePolicy = _buildPolicy();
  static final ForumWebViewVisualPolicy _forumDisplayPolicy = _buildPolicy(
    lateOnlyExtraSelectors: _pwaLateOnlySelectors,
  );
  static final ForumWebViewVisualPolicy _searchPolicy = _buildPolicy(
    lateOnlyExtraSelectors: _pwaLateOnlySelectors,
  );
  static final ForumWebViewVisualPolicy _threadDetailPolicy = _buildPolicy(
    earlyAndLateExtraSelectors: _threadDetailExtraSelectors,
  );
  static final ForumWebViewVisualPolicy _baselinePolicy = _buildPolicy();

  @override
  ForumWebViewVisualPolicy resolve(ForumWebViewPageKind pageKind) {
    switch (pageKind) {
      case ForumWebViewPageKind.home:
        return _homePolicy;
      case ForumWebViewPageKind.forumDisplay:
        return _forumDisplayPolicy;
      case ForumWebViewPageKind.threadDetail:
        return _threadDetailPolicy;
      case ForumWebViewPageKind.search:
        return _searchPolicy;
      case ForumWebViewPageKind.other:
        return _baselinePolicy;
    }
  }

  static ForumWebViewVisualPolicy _buildPolicy({
    Set<String> earlyAndLateExtraSelectors = const <String>{},
    Set<String> lateOnlyExtraSelectors = const <String>{},
  }) {
    final earlySelectors = Set<String>.unmodifiable(<String>{
      ..._baselineSelectors,
      ...earlyAndLateExtraSelectors,
    });
    final lateSelectors = Set<String>.unmodifiable(<String>{
      ..._baselineSelectors,
      ...earlyAndLateExtraSelectors,
      ...lateOnlyExtraSelectors,
    });
    return ForumWebViewVisualPolicy(
      earlyHiddenSelectors: earlySelectors,
      lateRemovedSelectors: lateSelectors,
      extraCss: _sharedExtraCss,
      useLoadingMaskUntilStable: true,
      disableHorizontalOverflow: true,
    );
  }
}
