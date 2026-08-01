import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/domain/services/forum_webview_visual_policy_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';

void main() {
  test('launch config preserves the edit URI and root-back behavior', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=10&pid=11',
    );
    final defaultConfig = ForumWebViewLaunchConfig(
      initialUri: Uri.parse('https://bbs.yamibo.com/'),
    );
    final config = ForumWebViewLaunchConfig(
      initialUri: uri,
      popOnRootBack: true,
      purpose: ForumWebViewHostPurpose.postEditFallback,
      completionTarget: const ForumWebViewCompletionTarget(
        tid: '10',
        pid: '11',
      ),
    );

    expect(defaultConfig.popOnRootBack, isFalse);
    expect(config.initialUri, uri);
    expect(config.popOnRootBack, isTrue);
    expect(config.purpose, ForumWebViewHostPurpose.postEditFallback);
    expect(config.completionTarget?.pid, '11');
  });

  test('post edit route results distinguish target redirects from returns', () {
    const result = ForumWebViewRouteResult(
      outcome: ForumWebViewRouteOutcome.observedTargetRedirect,
      serverMutationPossible: true,
    );

    expect(result.outcome, ForumWebViewRouteOutcome.observedTargetRedirect);
    expect(result.serverMutationPossible, isTrue);
  });

  test('edit URL stays other and keeps the baseline cleanup contract', () {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=10&pid=11',
    );
    final navigator = DefaultForumWebViewNavigator();
    final policy = const DefaultForumWebViewVisualPolicyResolver();

    expect(navigator.classify(uri), ForumWebViewPageKind.other);
    expect(
      policy.resolve(ForumWebViewPageKind.other).lateRemovedSelectors,
      containsAll(<String>['.footer.mt10.cl', '.foot.flex-box']),
    );
  });

  test('route factory returns a managed page route', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final factory = container.read(forumWebViewRouteFactoryProvider);
    final route = factory(
      ForumWebViewLaunchConfig(
        initialUri: Uri.parse(
          'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=10&pid=11',
        ),
        popOnRootBack: true,
      ),
    );

    expect(route, isA<PageRoute<void>>());
  });
}
