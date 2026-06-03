import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/tags/data/forum_tag_repository.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';

void main() {
  test('build defaults to home loading state', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    final state = await container.read(forumWebViewControllerProvider.future);

    expect(
      state.currentUri.toString(),
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    expect(state.pageKind, ForumWebViewPageKind.home);
    expect(state.fid, isNull);
    expect(state.tid, isNull);
    expect(state.boardName, isNull);
    expect(state.pageTitle, isNull);
    expect(state.canGoBack, isFalse);
    expect(state.isLoading, isTrue);
    expect(state.loadingProgress, 0);
  });

  test('onPageStarted updates current uri and page kind', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    container
        .read(forumWebViewControllerProvider.notifier)
        .onPageStarted(
          'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
        );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.pageKind, ForumWebViewPageKind.forumDisplay);
    expect(state.fid, '55');
    expect(state.isLoading, isTrue);
    expect(state.loadingProgress, 0);
  });

  test('onProgress updates loading progress while keeping loading state', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    container.read(forumWebViewControllerProvider.notifier).onProgress(42);

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.loadingProgress, 42);
    expect(state.isLoading, isTrue);
  });

  test('onPageFinished resolves board name and canGoBack', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    await container.read(forumWebViewControllerProvider.notifier).onPageFinished(
          rawUrl:
              'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
          pageTitle: '页面标题',
          canGoBack: true,
        );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.pageKind, ForumWebViewPageKind.forumDisplay);
    expect(state.fid, '55');
    expect(state.boardName, '综合区');
    expect(state.pageTitle, '页面标题');
    expect(state.canGoBack, isTrue);
    expect(state.isLoading, isFalse);
    expect(state.loadingProgress, 100);
  });

  test('thread detail keeps previous fid when url does not carry it', () async {
    final container = _createContainer();
    addTearDown(container.dispose);

    final controller = container.read(forumWebViewControllerProvider.notifier);
    controller.onPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );
    await controller.onPageFinished(
      rawUrl: 'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      pageTitle: '综合区页面',
      canGoBack: true,
    );
    controller.onPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
    await controller.onPageFinished(
      rawUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      pageTitle: '主题标题',
      canGoBack: true,
    );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.pageKind, ForumWebViewPageKind.threadDetail);
    expect(state.fid, '55');
    expect(state.tid, '123');
    expect(state.boardName, '综合区');
    expect(state.isLoading, isFalse);
    expect(state.loadingProgress, 100);
  });

  test('board name falls back to page title when tag lookup misses fid', () async {
    final container = _createContainer(
      repository: _FakeForumTagRepository(const <ForumBoardTagSet>[]),
    );
    addTearDown(container.dispose);

    await container.read(forumWebViewControllerProvider.notifier).onPageFinished(
          rawUrl:
              'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=66&mobile=2',
          pageTitle: '回退标题',
          canGoBack: false,
        );

    final state = await container.read(forumWebViewControllerProvider.future);
    expect(state.boardName, '回退标题');
    expect(state.canGoBack, isFalse);
  });
}

ProviderContainer _createContainer({
  ForumTagRepository? repository,
}) {
  return ProviderContainer(
    overrides: [
      forumTagRepositoryProvider.overrideWithValue(
        repository ?? _FakeForumTagRepository(_defaultBoards),
      ),
    ],
  );
}

const List<ForumBoardTagSet> _defaultBoards = <ForumBoardTagSet>[
  ForumBoardTagSet(
    fid: '55',
    name: '综合区',
    tags: <ForumTagDefinition>[],
  ),
];

class _FakeForumTagRepository implements ForumTagRepository {
  const _FakeForumTagRepository(this.boards);

  final List<ForumBoardTagSet> boards;

  @override
  Future<ForumTagLookup> loadLookup() async {
    return ForumTagLookup(boards);
  }
}
