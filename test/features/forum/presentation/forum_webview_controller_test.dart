import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';

void main() {
  test('build defaults to home loading state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = await container.read(forumWebViewControllerProvider.future);

    expect(
      state.currentUri.toString(),
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    expect(state.pageKind, ForumWebViewPageKind.home);
    expect(state.isLoading, isTrue);
    expect(state.loadingProgress, 0);
  });

  test('onPageStarted updates current uri and page kind', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(forumWebViewControllerProvider.notifier)
        .onPageStarted(
          'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
        );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.pageKind, ForumWebViewPageKind.forumDisplay);
    expect(state.isLoading, isTrue);
    expect(state.loadingProgress, 0);
  });

  test('onProgress updates loading progress while keeping loading state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(forumWebViewControllerProvider.notifier).onProgress(42);

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.loadingProgress, 42);
    expect(state.isLoading, isTrue);
  });

  test('onPageFinished marks load complete and classifies detail page', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(forumWebViewControllerProvider.notifier)
        .onPageFinished(
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
        );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.pageKind, ForumWebViewPageKind.threadDetail);
    expect(state.isLoading, isFalse);
    expect(state.loadingProgress, 100);
  });
}
