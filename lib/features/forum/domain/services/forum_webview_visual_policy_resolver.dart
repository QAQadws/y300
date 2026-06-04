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

  static const ForumWebViewVisualPolicy _managedSitePolicy =
      ForumWebViewVisualPolicy(
        earlyHiddenSelectors: <String>{
          '#header-padding',
          '.header.cl',
          '.footer.mt10.cl',
          '.foot.flex-box',
        },
        lateRemovedSelectors: <String>{
          '#header-padding',
          '.header.cl',
          '.footer.mt10.cl',
          '.foot.flex-box',
        },
        extraCss: '',
        useLoadingMaskUntilStable: true,
        disableHorizontalOverflow: true,
      );

  @override
  ForumWebViewVisualPolicy resolve(ForumWebViewPageKind pageKind) {
    switch (pageKind) {
      case ForumWebViewPageKind.home:
      case ForumWebViewPageKind.forumDisplay:
      case ForumWebViewPageKind.threadDetail:
      case ForumWebViewPageKind.search:
      case ForumWebViewPageKind.other:
        return _managedSitePolicy;
    }
  }
}
