import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';
import 'package:y300/features/forum/presentation/forum_display_controller.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/posting/domain/models/posting_target.dart';
import 'package:y300/features/posting/presentation/posting_composer_page.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

class ForumDisplayPage extends ConsumerWidget {
  const ForumDisplayPage({super.key, required this.fid, this.title = ''});

  final String fid;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = ForumDisplayArgs(fid: fid, title: title);
    final asyncState = ref.watch(forumDisplayControllerProvider(args));
    final controller = ref.read(forumDisplayControllerProvider(args).notifier);
    final state =
        asyncState.value ??
        ForumDisplayPageState.initial(fid: fid, title: title);

    return Scaffold(
      backgroundColor: _ForumDisplayPalette.background,
      appBar: AppBar(
        title: Text(state.title.isNotEmpty ? state.title : '帖子列表'),
        actions: [
          if (fid == '30')
            IconButton(
              key: const Key('forum-display-search-button'),
              tooltip: '搜索本版',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ForumSearchPage(
                      context: DiscuzSearchContext.curForum(srhfid: '30'),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.search),
            ),
        ],
      ),
      body: (asyncState.isLoading && state.threads.isEmpty)
          ? const _ForumDisplayInitialLoading()
          : state.errorMessage != null && state.threads.isEmpty
          ? _ForumDisplayErrorView(
              message: state.errorMessage!,
              onRetry: controller.refresh,
            )
          : RefreshIndicator(
              color: _ForumDisplayPalette.accent,
              onRefresh: controller.refresh,
              child: _ForumDisplayBody(
                state: state,
                onLoadMore: controller.loadMore,
                onLoadPrevious: controller.loadPreviousPage,
                onSelectPage: controller.loadPageNumber,
                onOpenFilter: controller.openFilter,
                onOpenThreadTag: controller.openThreadTag,
                onOpenThread: (thread) => _openThread(context, thread),
                onOpenTopEntry: (entry) => _openTopEntry(context, entry),
                onOpenSubForum: (subForum) => _openSubForum(context, subForum),
                onCompose: () => _openComposer(context, state),
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

class _ForumDisplayBody extends StatelessWidget {
  const _ForumDisplayBody({
    required this.state,
    required this.onLoadMore,
    required this.onLoadPrevious,
    required this.onSelectPage,
    required this.onOpenFilter,
    required this.onOpenThreadTag,
    required this.onOpenThread,
    required this.onOpenTopEntry,
    required this.onOpenSubForum,
    required this.onCompose,
  });

  final ForumDisplayPageState state;
  final VoidCallback onLoadMore;
  final VoidCallback onLoadPrevious;
  final ValueChanged<int> onSelectPage;
  final ValueChanged<ForumDisplayFilterItem> onOpenFilter;
  final ValueChanged<ForumThreadSummary> onOpenThreadTag;
  final ValueChanged<ForumThreadSummary> onOpenThread;
  final ValueChanged<ForumDisplayTopEntry> onOpenTopEntry;
  final ValueChanged<ForumDisplaySubForum> onOpenSubForum;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('forum-display-list'),
      padding: EdgeInsets.zero,
      children: [
        if (state.headImageUrl?.trim().isNotEmpty == true)
          _ForumHeadImage(url: state.headImageUrl!.trim(), label: state.title),
        _ForumDisplayHeader(state: state, onCompose: onCompose),
        if (state.primaryFilters.isNotEmpty)
          _FilterStrip(
            items: state.primaryFilters,
            dense: false,
            onSelected: onOpenFilter,
          ),
        if (state.typeFilters.isNotEmpty)
          _FilterStrip(
            items: state.typeFilters,
            dense: true,
            onSelected: onOpenFilter,
          ),
        if (state.subForums.isNotEmpty)
          _SubForumList(
            subForums: state.subForums,
            onOpenSubForum: onOpenSubForum,
          ),
        if (state.topEntries.isNotEmpty)
          _TopEntryList(entries: state.topEntries, onOpenEntry: onOpenTopEntry),
        if (state.threads.isEmpty)
          const _EmptyThreadList()
        else
          for (final thread in state.threads)
            _ThreadCard(
              thread: thread,
              onTap: () => onOpenThread(thread),
              onTapTag: () => onOpenThreadTag(thread),
            ),
        _LoadMoreSection(
          currentPage: state.currentPage,
          lastPage: state.lastPage,
          canLoadPrevious: state.currentPage > 1,
          hasMore: state.hasMore,
          isLoadingMore: state.isLoadingMore,
          onLoadPrevious: onLoadPrevious,
          onLoadMore: onLoadMore,
          onSelectPage: onSelectPage,
        ),
      ],
    );
  }
}

class _ForumHeadImage extends StatelessWidget {
  const _ForumHeadImage({required this.url, required this.label});

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('forum-display-head-image'),
      color: _ForumDisplayPalette.panel,
      child: Image.network(
        url,
        width: double.infinity,
        fit: BoxFit.fitWidth,
        semanticLabel: label.isEmpty ? '版块顶部图' : '$label 版块顶部图',
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox(
            height: 72,
            child: ColoredBox(
              color: _ForumDisplayPalette.disabled,
              child: Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: _ForumDisplayPalette.softText,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SubForumList extends StatelessWidget {
  const _SubForumList({required this.subForums, required this.onOpenSubForum});

  final List<ForumDisplaySubForum> subForums;
  final ValueChanged<ForumDisplaySubForum> onOpenSubForum;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('forum-display-sub-forums'),
      color: _ForumDisplayPalette.card,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(
        children: [
          for (final subForum in subForums)
            _SubForumTile(
              key: Key('forum-display-sub-forum-${subForum.fid}'),
              subForum: subForum,
              onTap: () => onOpenSubForum(subForum),
            ),
        ],
      ),
    );
  }
}

class _SubForumTile extends StatelessWidget {
  const _SubForumTile({super.key, required this.subForum, required this.onTap});

  final ForumDisplaySubForum subForum;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
        child: Row(
          children: [
            Container(
              width: 54,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 4),
              child: const Text(
                '子版块',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ForumDisplayPalette.title,
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SubForumIcon(url: subForum.iconUrl, label: subForum.title),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      subForum.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ForumDisplayPalette.title,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 54),
          ],
        ),
      ),
    );
  }
}

class _SubForumIcon extends StatelessWidget {
  const _SubForumIcon({required this.url, required this.label});

  final String? url;
  final String label;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    return SizedBox(
      width: 24,
      height: 24,
      child: imageUrl == null || imageUrl.isEmpty
          ? const Icon(
              Icons.forum_outlined,
              size: 20,
              color: _ForumDisplayPalette.softText,
            )
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              semanticLabel: label,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.forum_outlined,
                size: 20,
                color: _ForumDisplayPalette.softText,
              ),
            ),
    );
  }
}

class _ForumDisplayHeader extends StatelessWidget {
  const _ForumDisplayHeader({required this.state, required this.onCompose});

  final ForumDisplayPageState state;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _ForumDisplayPalette.panel,
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.title.isNotEmpty ? state.title : '帖子列表',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ForumDisplayPalette.title,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    _StatText(label: '今日', value: state.todayPosts),
                    _StatText(label: '主题', value: state.totalThreads),
                    _StatText(label: '排名', value: state.rank),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 32,
            child: FilledButton.icon(
              key: const Key('forum-display-compose-button'),
              onPressed: onCompose,
              icon: const Icon(Icons.edit, size: 15),
              label: const Text('发帖'),
              style: FilledButton.styleFrom(
                backgroundColor: _ForumDisplayPalette.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatText extends StatelessWidget {
  const _StatText({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$label: ',
        children: [
          TextSpan(
            text: value.toString(),
            style: const TextStyle(
              color: _ForumDisplayPalette.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      style: const TextStyle(
        color: _ForumDisplayPalette.muted,
        fontSize: 11,
        height: 1.2,
      ),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({
    required this.items,
    required this.dense,
    required this.onSelected,
  });

  final List<ForumDisplayFilterItem> items;
  final bool dense;
  final ValueChanged<ForumDisplayFilterItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: dense ? 34 : 42,
      decoration: const BoxDecoration(
        color: _ForumDisplayPalette.panel,
        border: Border(
          top: BorderSide(color: _ForumDisplayPalette.border),
          bottom: BorderSide(color: _ForumDisplayPalette.border),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12),
        itemCount: items.length,
        separatorBuilder: (context, index) => SizedBox(width: dense ? 6 : 14),
        itemBuilder: (context, index) {
          final item = items[index];
          return Center(
            child: InkWell(
              key: Key('forum-display-filter-${item.label}'),
              borderRadius: BorderRadius.circular(4),
              onTap: item.isSelected ? null : () => onSelected(item),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 4 : 2,
                  vertical: 7,
                ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: item.isSelected
                        ? _ForumDisplayPalette.accent
                        : _ForumDisplayPalette.softText,
                    fontSize: dense ? 12 : 13,
                    fontWeight: item.isSelected
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopEntryList extends StatelessWidget {
  const _TopEntryList({required this.entries, required this.onOpenEntry});

  final List<ForumDisplayTopEntry> entries;
  final ValueChanged<ForumDisplayTopEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _ForumDisplayPalette.pinnedPanel,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final entry in entries)
            _TopEntryTile(
              key: ValueKey('forum-top-${entry.tid}-${entry.title}'),
              entry: entry,
              onTap: () => onOpenEntry(entry),
            ),
        ],
      ),
    );
  }
}

class _TopEntryTile extends StatelessWidget {
  const _TopEntryTile({super.key, required this.entry, required this.onTap});

  final ForumDisplayTopEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        _parseColor(entry.titleColorHex) ??
        (entry.isAnnouncement
            ? _ForumDisplayPalette.warning
            : _ForumDisplayPalette.accent);
    return InkWell(
      onTap: entry.tid.trim().isEmpty ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SmallBadge(
              label: entry.badgeLabel.isNotEmpty
                  ? entry.badgeLabel
                  : (entry.isAnnouncement ? '公告' : '置顶'),
              backgroundColor: entry.isAnnouncement
                  ? _ForumDisplayPalette.warning
                  : _ForumDisplayPalette.accent,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({
    required this.thread,
    required this.onTap,
    required this.onTapTag,
  });

  final ForumThreadSummary thread;
  final VoidCallback onTap;
  final VoidCallback onTapTag;

  @override
  Widget build(BuildContext context) {
    final titleColor =
        _parseColor(thread.titleColorHex) ?? _ForumDisplayPalette.threadTitle;
    return InkWell(
      key: Key('forum-thread-${thread.tid}'),
      onTap: onTap,
      child: Container(
        color: _ForumDisplayPalette.card,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        margin: const EdgeInsets.only(top: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(url: thread.avatarUrl, author: thread.author),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ThreadAuthorRow(thread: thread),
                  const SizedBox(height: 7),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (thread.badgeLabel?.isNotEmpty == true) ...[
                        _SmallBadge(
                          label: thread.badgeLabel!,
                          backgroundColor: thread.isLocked
                              ? _ForumDisplayPalette.warning
                              : _ForumDisplayPalette.accent,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          thread.subject,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 15,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (thread.excerpt.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      thread.excerpt.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ForumDisplayPalette.bodyText,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _ThreadFooter(thread: thread, onTapTag: onTapTag),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadAuthorRow extends StatelessWidget {
  const _ThreadAuthorRow({required this.thread});

  final ForumThreadSummary thread;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            thread.author.isNotEmpty ? thread.author : '匿名',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ForumDisplayPalette.author,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ),
        if (thread.dateline.trim().isNotEmpty)
          Text(
            thread.dateline.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ForumDisplayPalette.softText,
              fontSize: 10,
            ),
          ),
      ],
    );
  }
}

class _ThreadFooter extends StatelessWidget {
  const _ThreadFooter({required this.thread, required this.onTapTag});

  final ForumThreadSummary thread;
  final VoidCallback onTapTag;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MetricChip(icon: Icons.visibility_outlined, value: thread.views),
        const SizedBox(width: 5),
        _MetricChip(icon: Icons.chat_bubble_outline, value: thread.replies),
        const Spacer(),
        if (thread.sourceTagName?.trim().isNotEmpty == true)
          Flexible(
            child: InkWell(
              key: Key('forum-thread-tag-${thread.tid}'),
              borderRadius: BorderRadius.circular(4),
              onTap: thread.sourceTagUrl?.trim().isNotEmpty == true
                  ? onTapTag
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  '#${thread.sourceTagName!.trim()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: _ForumDisplayPalette.tag,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.author});

  final String? url;
  final String author;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFFEAD5A9),
      foregroundColor: _ForumDisplayPalette.accent,
      backgroundImage: imageUrl == null || imageUrl.isEmpty
          ? null
          : NetworkImage(imageUrl),
      child: imageUrl == null || imageUrl.isEmpty
          ? Text(
              _authorInitial(author),
              style: const TextStyle(fontWeight: FontWeight.w700),
            )
          : null,
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: _ForumDisplayPalette.metricBackground,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _ForumDisplayPalette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _ForumDisplayPalette.softText),
          const SizedBox(width: 3),
          Text(
            value.toString(),
            style: const TextStyle(
              color: _ForumDisplayPalette.softText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label, required this.backgroundColor});

  final String label;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LoadMoreSection extends StatelessWidget {
  const _LoadMoreSection({
    required this.currentPage,
    required this.lastPage,
    required this.canLoadPrevious,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadPrevious,
    required this.onLoadMore,
    required this.onSelectPage,
  });

  final int currentPage;
  final int? lastPage;
  final bool canLoadPrevious;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadPrevious;
  final VoidCallback onLoadMore;
  final ValueChanged<int> onSelectPage;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _ForumDisplayPalette.background,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageButton(
            key: const Key('forum-display-prev-page-button'),
            label: '上一页',
            enabled: canLoadPrevious && !isLoadingMore,
            onPressed: onLoadPrevious,
          ),
          const SizedBox(width: 8),
          _CurrentPageButton(
            currentPage: currentPage > 0 ? currentPage : 1,
            lastPage: lastPage,
            enabled: !isLoadingMore,
            onSelected: onSelectPage,
          ),
          const SizedBox(width: 8),
          if (isLoadingMore)
            const SizedBox(
              width: 72,
              height: 34,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            _PageButton(
              key: const Key('forum-display-load-more-button'),
              label: hasMore ? '下一页' : '没有更多',
              enabled: hasMore,
              onPressed: onLoadMore,
            ),
        ],
      ),
    );
  }
}

class _CurrentPageButton extends StatelessWidget {
  const _CurrentPageButton({
    required this.currentPage,
    required this.lastPage,
    required this.enabled,
    required this.onSelected,
  });

  final int currentPage;
  final int? lastPage;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextButton(
        key: const Key('forum-display-current-page-button'),
        onPressed: enabled ? () => _showPagePicker(context) : null,
        style: TextButton.styleFrom(
          backgroundColor: _ForumDisplayPalette.card,
          disabledForegroundColor: _ForumDisplayPalette.disabledText,
          foregroundColor: _ForumDisplayPalette.title,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: _ForumDisplayPalette.border),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        child: Text('第$currentPage页'),
      ),
    );
  }

  Future<void> _showPagePicker(BuildContext context) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => _ForumDisplayPagePickerDialog(
        currentPage: currentPage,
        lastPage: lastPage,
      ),
    );
    if (selected != null) {
      onSelected(selected);
    }
  }
}

class _ForumDisplayPagePickerDialog extends StatefulWidget {
  const _ForumDisplayPagePickerDialog({
    required this.currentPage,
    required this.lastPage,
  });

  final int currentPage;
  final int? lastPage;

  @override
  State<_ForumDisplayPagePickerDialog> createState() =>
      _ForumDisplayPagePickerDialogState();
}

class _ForumDisplayPagePickerDialogState
    extends State<_ForumDisplayPagePickerDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPage.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lastPage = widget.lastPage;
    return AlertDialog(
      title: const Text('选择页码'),
      content: TextField(
        key: const Key('forum-display-page-input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: lastPage == null ? '页码' : '页码（1-$lastPage）',
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('forum-display-page-confirm-button'),
          onPressed: () => _submit(context),
          child: const Text('跳转'),
        ),
      ],
    );
  }

  void _submit(BuildContext context) {
    final page = int.tryParse(_controller.text.trim());
    final lastPage = widget.lastPage;
    if (page == null || page < 1) {
      setState(() => _errorText = '请输入有效页码');
      return;
    }
    if (lastPage != null && page > lastPage) {
      setState(() => _errorText = '不能超过第$lastPage页');
      return;
    }
    Navigator.of(context).pop(page);
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          backgroundColor: enabled
              ? _ForumDisplayPalette.card
              : _ForumDisplayPalette.disabled,
          disabledForegroundColor: _ForumDisplayPalette.disabledText,
          foregroundColor: _ForumDisplayPalette.accent,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: _ForumDisplayPalette.border),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

class _EmptyThreadList extends StatelessWidget {
  const _EmptyThreadList();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _ForumDisplayPalette.card,
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: const Text(
        '暂无帖子',
        style: TextStyle(color: _ForumDisplayPalette.softText, fontSize: 13),
      ),
    );
  }
}

class _ForumDisplayInitialLoading extends StatelessWidget {
  const _ForumDisplayInitialLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _ForumDisplayPalette.background,
      alignment: Alignment.center,
      child: const CircularProgressIndicator(
        color: _ForumDisplayPalette.accent,
      ),
    );
  }
}

class _ForumDisplayErrorView extends StatelessWidget {
  const _ForumDisplayErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _ForumDisplayPalette.background,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ForumDisplayPalette.title),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('forum-display-retry-button'),
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: _ForumDisplayPalette.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

String _authorInitial(String author) {
  final trimmed = author.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

Color? _parseColor(String? source) {
  final value = source?.trim();
  if (value == null || value.isEmpty || !value.startsWith('#')) {
    return null;
  }
  final hex = value.substring(1);
  if (hex.length == 3) {
    final expanded = hex.split('').map((char) => '$char$char').join();
    return Color(int.parse('FF$expanded', radix: 16));
  }
  if (hex.length == 6) {
    return Color(int.parse('FF$hex', radix: 16));
  }
  if (hex.length == 8) {
    return Color(int.parse(hex, radix: 16));
  }
  return null;
}

class _ForumDisplayPalette {
  const _ForumDisplayPalette._();

  static const background = Color(0xFFFFF7D8);
  static const panel = Color(0xFFFFF2C7);
  static const pinnedPanel = Color(0xFFFFF0BC);
  static const card = Color(0xFFFFF5CE);
  static const metricBackground = Color(0xFFFFEAB9);
  static const disabled = Color(0xFFF7E8BE);
  static const border = Color(0xFFEADAA7);
  static const accent = Color(0xFF7A210F);
  static const warning = Color(0xFFE7493D);
  static const title = Color(0xFF6E3B23);
  static const threadTitle = Color(0xFF6F3B23);
  static const author = Color(0xFFB26B56);
  static const bodyText = Color(0xFF9A7A57);
  static const muted = Color(0xFFB58E6E);
  static const softText = Color(0xFFC09B72);
  static const disabledText = Color(0xFFD5BF92);
  static const tag = Color(0xFF9B5B41);
}
