import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_visual_policy_resolver.dart';

void main() {
  const resolver = DefaultForumWebViewVisualPolicyResolver();
  const baselineSelectors = <String>{
    '#header-padding',
    '.header.cl',
    '.footer.mt10.cl',
    '.foot.flex-box',
  };
  const homeAndForumDisplayExtraSelectors = <String>{
    '.foot_height',
    '.foot-pwa',
  };
  const threadDetailExtraSelectors = <String>{
    '.foot.foot_reply.flex-box.cl',
    '.foot_height_view',
  };

  void expectSharedPolicyShape(ForumWebViewPageKind pageKind) {
    final policy = resolver.resolve(pageKind);
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

  test('home and forum display include their footer cleanup selectors', () {
    for (final pageKind in <ForumWebViewPageKind>[
      ForumWebViewPageKind.home,
      ForumWebViewPageKind.forumDisplay,
    ]) {
      final policy = resolver.resolve(pageKind);
      expect(
        policy.earlyHiddenSelectors,
        <String>{
          ...baselineSelectors,
          ...homeAndForumDisplayExtraSelectors,
        },
      );
      expect(
        policy.lateRemovedSelectors,
        <String>{
          ...baselineSelectors,
          ...homeAndForumDisplayExtraSelectors,
        },
      );
      expect(policy.earlyHiddenSelectors, isNot(contains('.foot.foot_reply.flex-box.cl')));
      expect(policy.earlyHiddenSelectors, isNot(contains('.foot_height_view')));
      expectSharedPolicyShape(pageKind);
    }
  });

  test('thread detail includes reply footer cleanup selectors', () {
    final policy = resolver.resolve(ForumWebViewPageKind.threadDetail);

    expect(
      policy.earlyHiddenSelectors,
      <String>{
        ...baselineSelectors,
        ...threadDetailExtraSelectors,
      },
    );
    expect(
      policy.lateRemovedSelectors,
      <String>{
        ...baselineSelectors,
        ...threadDetailExtraSelectors,
      },
    );
    expect(policy.earlyHiddenSelectors, isNot(contains('.foot_height')));
    expect(policy.earlyHiddenSelectors, isNot(contains('.foot-pwa')));
    expectSharedPolicyShape(ForumWebViewPageKind.threadDetail);
  });

  test('search and other keep the managed-site baseline selectors only', () {
    for (final pageKind in <ForumWebViewPageKind>[
      ForumWebViewPageKind.search,
      ForumWebViewPageKind.other,
    ]) {
      final policy = resolver.resolve(pageKind);
      expect(policy.earlyHiddenSelectors, baselineSelectors);
      expect(policy.lateRemovedSelectors, baselineSelectors);
      expect(policy.earlyHiddenSelectors, isNot(contains('.foot_height')));
      expect(policy.earlyHiddenSelectors, isNot(contains('.foot-pwa')));
      expect(
        policy.earlyHiddenSelectors,
        isNot(contains('.foot.foot_reply.flex-box.cl')),
      );
      expect(policy.earlyHiddenSelectors, isNot(contains('.foot_height_view')));
      expectSharedPolicyShape(pageKind);
    }
  });
}
