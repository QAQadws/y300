import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';
import 'package:y300/features/forum/presentation/forum_display_controller.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_widgets.dart';
import 'package:y300/features/posting/domain/models/posting_target.dart';
import 'package:y300/features/posting/presentation/posting_composer_page.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

class ForumDisplayPage extends ConsumerStatefulWidget {
  const ForumDisplayPage({super.key, required this.fid, this.title = ''});

  final String fid;
  final String title;

  @override
  ConsumerState<ForumDisplayPage> createState() => _ForumDisplayPageState();
}

class _ForumDisplayPageState extends ConsumerState<ForumDisplayPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _filterAnchorKey = GlobalKey();
  final GlobalKey _headImageKey = GlobalKey();
  double? _lastKnownHeadImageExtent;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = ForumDisplayArgs(fid: widget.fid, title: widget.title);
    final asyncState = ref.watch(forumDisplayControllerProvider(args));
    final controller = ref.read(forumDisplayControllerProvider(args).notifier);
    final state =
        asyncState.value ??
        ForumDisplayPageState.initial(fid: widget.fid, title: widget.title);
    final hasHeadImage = state.headImageUrl?.trim().isNotEmpty == true;
    if (!hasHeadImage) {
      _lastKnownHeadImageExtent = null;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _captureHeadImageExtent();
      });
    }
    final theme = Theme.of(context);
    final palette = ForumDisplayThemePalette.resolve(theme);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: _ForumDisplayAppBarTitle(state: state),
        actions: [
          if (widget.fid == '30')
            IconButton(
              key: const Key('forum-display-search-button'),
              tooltip: '搜索本版',
              onPressed: () => _openSearch(context),
              icon: const Icon(Icons.search),
            ),
          IconButton(
            key: const Key('forum-display-compose-button'),
            tooltip: '发帖',
            onPressed: () => _openComposer(context, state),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: (asyncState.isLoading && state.threads.isEmpty)
          ? const ForumDisplayInitialLoading()
          : state.errorMessage != null && state.threads.isEmpty
          ? ForumDisplayErrorView(
              message: state.errorMessage!,
              onRetry: controller.refresh,
            )
          : RefreshIndicator(
              color: theme.colorScheme.primary,
              onRefresh: controller.refresh,
              child: ForumDisplayContent(
                state: state,
                scrollController: _scrollController,
                filterAnchorKey: _filterAnchorKey,
                headImageKey: _headImageKey,
                onLoadMore: () => _runAndReturnToFilter(controller.loadMore),
                onLoadPrevious: () =>
                    _runAndReturnToFilter(controller.loadPreviousPage),
                onSelectPage: (page) => _runAndReturnToFilter(
                  () => controller.loadPageNumber(page),
                ),
                onOpenFilter: (item) =>
                    _runAndReturnToFilter(() => controller.openFilter(item)),
                onOpenThreadTag: (thread) => _runAndReturnToFilter(
                  () => controller.openThreadTag(thread),
                ),
                onOpenThread: (thread) => _openThread(context, thread),
                onCopyThreadLink: (thread) => _copyThreadLink(context, thread),
                onOpenTopEntry: (entry) => _openTopEntry(context, entry),
                onOpenSubForum: (subForum) => _openSubForum(context, subForum),
              ),
            ),
    );
  }

  Future<void> _runAndReturnToFilter(FutureOr<void> Function() action) async {
    await action();
    await _scrollToFilterStart();
  }

  Future<void> _scrollToFilterStart() async {
    if (!mounted) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final target = _filterStartScrollOffset(position);
    final clampedTarget = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((position.pixels - clampedTarget).abs() < 0.5) {
      return;
    }
    await _scrollController.animateTo(
      clampedTarget,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  double _filterStartScrollOffset(ScrollPosition position) {
    final headImageContext = _headImageKey.currentContext;
    if (headImageContext == null) {
      return position.minScrollExtent;
    }

    final headImageRenderObject = headImageContext.findRenderObject();
    if (headImageRenderObject is RenderBox && headImageRenderObject.hasSize) {
      final extent = _cacheHeadImageExtent(headImageRenderObject);
      if (extent != null) {
        return extent;
      }
    }

    if (_lastKnownHeadImageExtent != null) {
      return _lastKnownHeadImageExtent!;
    }

    return _filterScrollOffset() ?? position.minScrollExtent;
  }

  void _captureHeadImageExtent() {
    if (!mounted) {
      return;
    }
    final renderObject = _headImageKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      _cacheHeadImageExtent(renderObject);
    }
  }

  double? _cacheHeadImageExtent(RenderBox renderObject) {
    final extent = renderObject.size.height;
    if (extent <= 0) {
      return null;
    }
    _lastKnownHeadImageExtent = extent;
    return extent;
  }

  double? _filterScrollOffset() {
    final anchorContext = _filterAnchorKey.currentContext;
    final renderObject = anchorContext?.findRenderObject();
    if (renderObject == null ||
        !renderObject.attached ||
        !_scrollController.hasClients) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    return viewport?.getOffsetToReveal(renderObject, 0).offset;
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ForumSearchPage(
          context: DiscuzSearchContext.curForum(srhfid: '30'),
        ),
      ),
    );
  }

  void _openThread(BuildContext context, ForumThreadSummary thread) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ThreadDetailPage(tid: thread.tid, subject: thread.subject),
      ),
    );
  }

  Future<void> _copyThreadLink(
    BuildContext context,
    ForumThreadSummary thread,
  ) async {
    final url = _threadLinkForCopy(thread);
    if (url == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制帖子链接')));
  }

  String? _threadLinkForCopy(ForumThreadSummary thread) {
    final threadUrl = thread.threadUrl?.trim();
    if (threadUrl != null && threadUrl.isNotEmpty) {
      return threadUrl;
    }
    final tid = thread.tid.trim();
    if (tid.isEmpty) {
      return null;
    }
    return Uri.parse(AppConfig.siteBaseUrl)
        .replace(
          path: '/forum.php',
          queryParameters: <String, String>{
            'mod': 'viewthread',
            'tid': tid,
            'mobile': '2',
          },
        )
        .toString();
  }

  void _openTopEntry(BuildContext context, ForumDisplayTopEntry entry) {
    if (entry.tid.trim().isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(tid: entry.tid, subject: entry.title),
      ),
    );
  }

  void _openSubForum(BuildContext context, ForumDisplaySubForum subForum) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ForumDisplayPage(fid: subForum.fid, title: subForum.title),
      ),
    );
  }

  void _openComposer(BuildContext context, ForumDisplayPageState state) {
    Navigator.of(context).push(
      MaterialPageRoute<PostingComposerResult>(
        builder: (_) => PostingComposerPage(
          args: PostingComposerArgs(target: PostingTarget(fid: state.fid)),
        ),
      ),
    );
  }
}

class _ForumDisplayAppBarTitle extends StatelessWidget {
  const _ForumDisplayAppBarTitle({required this.state});

  final ForumDisplayPageState state;

  @override
  Widget build(BuildContext context) {
    final textStyle = DefaultTextStyle.of(context).style;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.title.isNotEmpty ? state.title : '帖子列表',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 1),
        DefaultTextStyle.merge(
          style: textStyle.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
          child: Row(
            key: const Key('forum-display-appbar-stats'),
            mainAxisSize: MainAxisSize.max,
            children: [
              _AppBarStatText(label: '今日', value: state.todayPosts),
              const SizedBox(width: 10),
              _AppBarStatText(label: '主题', value: state.totalThreads),
              const SizedBox(width: 10),
              _AppBarStatText(label: '排名', value: state.rank),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppBarStatText extends StatelessWidget {
  const _AppBarStatText({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Text(
        '$label $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
