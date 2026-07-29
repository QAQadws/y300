import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';
import 'package:y300/features/forum/presentation/forum_content_projection_providers.dart';
import 'package:y300/features/forum/presentation/forum_display_content_projection.dart';
import 'package:y300/features/forum/presentation/forum_display_content_projector.dart';
import 'package:y300/features/forum/presentation/forum_display_controller.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/forum/presentation/forum_text_resolver.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_widgets.dart';
import 'package:y300/features/posting/domain/models/posting_target.dart';
import 'package:y300/features/posting/presentation/posting_composer_page.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/shared/widgets/forum_pull_to_refresh.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);
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
    final searchFid = _searchFidFor(state);
    final mode = ref.watch(appServerContentConversionModeProvider);
    final projection = _projectionOrRaw(
      state,
      mode: mode,
      candidate: ref
          .watch(forumDisplayContentProjectionProvider(args))
          .asData
          ?.value,
    );

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: NavigationToolbar.kMiddleSpacing,
          ),
          child: _ForumDisplayAppBarTitle(projection: projection),
        ),
        actions: [
          if (searchFid != null)
            IconButton(
              key: const Key('forum-display-search-button'),
              tooltip: l10n.forumDisplaySearch,
              onPressed: () => _openSearch(context, searchFid),
              icon: const Icon(Icons.search),
            ),
          IconButton(
            key: const Key('forum-display-compose-button'),
            tooltip: l10n.forumDisplayCreateThread,
            onPressed: () => _openComposer(context, state),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: (asyncState.isLoading && state.threads.isEmpty)
          ? const ForumDisplayInitialLoading()
          : (state.failure != null || state.errorMessage != null) &&
                state.threads.isEmpty
          ? ForumDisplayErrorView(
              failure: state.failure,
              legacyDetail: state.errorMessage,
              onRetry: () => controller.refresh(forceNetwork: true),
            )
          : ForumPullToRefresh(
              onRefresh: () => controller.refresh(forceNetwork: true),
              child: ForumDisplayContent(
                projection: projection,
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
                onOpenThread: (thread) => _openThread(context, state, thread),
                onCopyThreadLink: (thread) => _copyThreadLink(context, thread),
                onOpenTopEntry: (entry) => _openTopEntry(context, state, entry),
                onOpenSubForum: (subForum) => _openSubForum(context, subForum),
              ),
            ),
    );
  }

  ForumDisplayContentProjection _projectionOrRaw(
    ForumDisplayPageState source, {
    required TextConversionMode mode,
    required ForumDisplayContentProjection? candidate,
  }) {
    final revision = ForumDisplayContentProjector.sourceRevisionFor(source);
    if (candidate != null &&
        candidate.mode == mode &&
        candidate.sourceRevision == revision) {
      return candidate;
    }
    return ForumDisplayContentProjection.raw(source, mode: mode);
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

  String? _searchFidFor(ForumDisplayPageState state) {
    final stateFid = state.fid.trim();
    if (stateFid.isNotEmpty) {
      return stateFid;
    }
    final widgetFid = widget.fid.trim();
    return widgetFid.isEmpty ? null : widgetFid;
  }

  void _openSearch(BuildContext context, String fid) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ForumSearchPage(context: DiscuzSearchContext.curForum(srhfid: fid)),
      ),
    );
  }

  void _openThread(
    BuildContext context,
    ForumDisplayPageState state,
    ForumThreadSummary thread,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(
          tid: thread.tid,
          subject: thread.subject,
          initialForumName: _forumNameForThreadDetail(state),
        ),
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
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).forumDisplayCopiedLink),
        ),
      );
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

  void _openTopEntry(
    BuildContext context,
    ForumDisplayPageState state,
    ForumDisplayTopEntry entry,
  ) {
    if (entry.tid.trim().isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(
          tid: entry.tid,
          subject: entry.title,
          initialForumName: _forumNameForThreadDetail(state),
        ),
      ),
    );
  }

  String? _forumNameForThreadDetail(ForumDisplayPageState state) {
    final title = state.title.trim();
    return title.isEmpty ? null : title;
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
  const _ForumDisplayAppBarTitle({required this.projection});

  final ForumDisplayContentProjection projection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textStyle = DefaultTextStyle.of(context).style;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ForumTextResolver.forumDisplayTitle(l10n, projection.displayTitle),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 1),
        DefaultTextStyle.merge(
          style: textStyle.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
          child: Row(
            key: const Key('forum-display-appbar-stats'),
            mainAxisSize: MainAxisSize.min,
            children: [
              _AppBarStatText(
                label: l10n.forumDisplayToday,
                value: projection.sourceState.todayPosts,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: _AppBarStatText(
                  label: l10n.forumDisplayThreads,
                  value: projection.sourceState.totalThreads,
                ),
              ),
              const SizedBox(width: 10),
              _AppBarStatText(
                label: l10n.forumDisplayRank,
                value: projection.sourceState.rank,
              ),
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
    return Text('$label $value', maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

Widget forumDisplayPreviewShell(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: Scaffold(body: SafeArea(child: child)),
  );
}

@Preview(
  name: 'Forum display thread card',
  group: 'Forum/Display',
  size: Size(393, 260),
  wrapper: forumDisplayPreviewShell,
)
Widget forumDisplayThreadCardPreview() {
  return ForumDisplayContent(
    projection: ForumDisplayContentProjection.raw(
      ForumDisplayPageState(
        fid: '33',
        title: '海域区',
        currentPage: 1,
        hasMore: false,
        isLoadingInitial: false,
        isLoadingMore: false,
        threads: [_forumDisplayPreviewThread],
        query: const ForumDisplayQuery(fid: '33'),
        todayPosts: 42,
        totalThreads: 120345,
        rank: 3,
        lastPage: 1,
      ),
      mode: TextConversionMode.none,
    ),
    scrollController: ScrollController(),
    filterAnchorKey: GlobalKey(),
    headImageKey: GlobalKey(),
    onLoadMore: () {},
    onLoadPrevious: () {},
    onSelectPage: (_) {},
    onOpenFilter: (_) {},
    onOpenThreadTag: (_) {},
    onOpenThread: (_) {},
    onCopyThreadLink: (_) {},
    onOpenTopEntry: (_) {},
    onOpenSubForum: (_) {},
  );
}

final ForumThreadSummary _forumDisplayPreviewThread = ForumThreadSummary(
  tid: 'preview-thread',
  typeid: '86',
  sourceTagName: '讨论',
  subject: '后面楼主参加活动的应该就是梅小雪那篇武侠了吧',
  author: '蜥蜴少女与神明',
  replies: 128,
  views: 4096,
  dateline: '2026-06-23 12:48',
  uid: '278948',
  avatarUrl:
      'https://bbs.yamibo.com/uc_server/data/avatar/000/27/89/48_avatar_small.jpg',
  authorUrl: 'https://bbs.yamibo.com/home.php?mod=space&uid=278948',
  threadUrl: 'https://bbs.yamibo.com/thread-preview-1-1.html',
  excerpt: '那篇很好啊我很喜欢，角色之间的互动很轻盈，读起来像是在夏天的海边慢慢展开的一封信。',
  sourceTagUrl:
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=33&typeid=86',
  badgeLabel: '投票',
);
