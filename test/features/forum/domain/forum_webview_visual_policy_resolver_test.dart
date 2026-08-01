import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
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
  const pwaLateOnlySelectors = <String>{'.foot_height', '.foot-pwa'};
  const threadDetailExtraSelectors = <String>{
    '.foot.foot_reply.flex-box.cl',
    '.foot_height_view',
  };

  void expectSharedPolicyShape(ForumWebViewPageKind pageKind) {
    final policy = resolver.resolve(pageKind);
    expect(policy.disableHorizontalOverflow, isTrue);
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

  test('home keeps the managed-site baseline selectors only', () {
    final policy = resolver.resolve(ForumWebViewPageKind.home);

    expect(policy.earlyHiddenSelectors, baselineSelectors);
    expect(policy.lateRemovedSelectors, baselineSelectors);
    expect(policy.earlyHiddenSelectors, isNot(contains('.foot_height')));
    expect(policy.earlyHiddenSelectors, isNot(contains('.foot-pwa')));
    expect(
      policy.earlyHiddenSelectors,
      isNot(contains('.foot.foot_reply.flex-box.cl')),
    );
    expect(policy.earlyHiddenSelectors, isNot(contains('.foot_height_view')));
    expectSharedPolicyShape(ForumWebViewPageKind.home);
  });

  test('forum display and search keep pwa cleanup late-only', () {
    for (final pageKind in <ForumWebViewPageKind>[
      ForumWebViewPageKind.forumDisplay,
      ForumWebViewPageKind.search,
    ]) {
      final policy = resolver.resolve(pageKind);
      expect(policy.earlyHiddenSelectors, baselineSelectors);
      expect(policy.lateRemovedSelectors, <String>{
        ...baselineSelectors,
        ...pwaLateOnlySelectors,
      });
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

  test('thread detail includes reply footer cleanup selectors', () {
    final policy = resolver.resolve(ForumWebViewPageKind.threadDetail);

    expect(policy.earlyHiddenSelectors, <String>{
      ...baselineSelectors,
      ...threadDetailExtraSelectors,
    });
    expect(policy.lateRemovedSelectors, <String>{
      ...baselineSelectors,
      ...threadDetailExtraSelectors,
    });
    expect(policy.earlyHiddenSelectors, isNot(contains('.foot_height')));
    expect(policy.earlyHiddenSelectors, isNot(contains('.foot-pwa')));
    expectSharedPolicyShape(ForumWebViewPageKind.threadDetail);
  });

  test('other keeps the managed-site baseline selectors only', () {
    final policy = resolver.resolve(ForumWebViewPageKind.other);

    expect(policy.earlyHiddenSelectors, baselineSelectors);
    expect(policy.lateRemovedSelectors, baselineSelectors);
    expect(policy.earlyHiddenSelectors, isNot(contains('.foot_height')));
    expect(policy.earlyHiddenSelectors, isNot(contains('.foot-pwa')));
    expect(
      policy.earlyHiddenSelectors,
      isNot(contains('.foot.foot_reply.flex-box.cl')),
    );
    expect(policy.earlyHiddenSelectors, isNot(contains('.foot_height_view')));
    expectSharedPolicyShape(ForumWebViewPageKind.other);
  });

  test('other chrome cleanup preserves the post edit form and save action', () {
    final policy = resolver.resolve(ForumWebViewPageKind.other);
    final document = html_parser.parse(
      File(
        'test/fixtures/thread/post_edit/mobile_post_edit_form.html',
      ).readAsStringSync(encoding: utf8),
    );
    final removedElements = <html_dom.Element>{};
    for (final selector in <String>{
      ...policy.earlyHiddenSelectors,
      ...policy.lateRemovedSelectors,
    }) {
      final matches = document.querySelectorAll(selector);
      expect(matches, isNotEmpty, reason: 'Fixture must exercise $selector.');
      removedElements.addAll(matches);
    }

    for (final selector in <String>[
      '#postform',
      '#needmessage',
      '#imglist',
      '.post_btn',
      '#postsubmit',
    ]) {
      html_dom.Element? ancestor = document.querySelector(selector);
      expect(ancestor, isNotNull, reason: 'Missing protected $selector.');
      while (ancestor != null) {
        expect(
          removedElements,
          isNot(contains(ancestor)),
          reason: '$selector must not be inside removable WebView chrome.',
        );
        ancestor = ancestor.parent;
      }
    }
  });

  test('managed profile pages reuse other chrome cleanup policy', () {
    final policy = resolver.resolve(ForumWebViewPageKind.other);

    expect(policy.earlyHiddenSelectors, contains('#header-padding'));
    expect(policy.earlyHiddenSelectors, contains('.header.cl'));
    expect(policy.lateRemovedSelectors, contains('.footer.mt10.cl'));
    expect(policy.lateRemovedSelectors, contains('.foot.flex-box'));
    expectSharedPolicyShape(ForumWebViewPageKind.other);
  });
}
