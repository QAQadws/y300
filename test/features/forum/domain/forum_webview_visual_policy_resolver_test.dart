import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_visual_policy_resolver.dart';

void main() {
  const resolver = DefaultForumWebViewVisualPolicyResolver();
  const expectedSelectors = <String>{
    '#header-padding',
    '.header.cl',
    '.footer.mt10.cl',
    '.foot.flex-box',
  };

  test('all page kinds use the managed-site baseline policy', () {
    for (final pageKind in ForumWebViewPageKind.values) {
      final policy = resolver.resolve(pageKind);
      expect(policy.earlyHiddenSelectors, expectedSelectors);
      expect(policy.lateRemovedSelectors, expectedSelectors);
      expect(policy.disableHorizontalOverflow, isTrue);
      expect(policy.useLoadingMaskUntilStable, isTrue);
      expect(policy.extraCss, isNotEmpty);
      expect(
        policy.extraCss,
        contains(
          'html, body { margin: 0 !important; padding: 0 !important; background: transparent !important; }',
        ),
      );
      expect(
        policy.extraCss,
        contains(
          'img, video, svg, canvas, iframe { max-width: 100% !important; height: auto !important; }',
        ),
      );
    }
  });
}
