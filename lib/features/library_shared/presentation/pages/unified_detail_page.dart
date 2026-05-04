import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/controllers/unified_detail_controller.dart';

/// 统一详情页骨架（Phase 4）
///
/// 设计要点：
/// 1. 顶部视觉区是一个整体：背景模糊图 + 封面 + 元信息。
/// 2. AppBar 标题在顶部展开态隐藏，滚动折叠到阈值后再显示。
/// 3. 详情逻辑仅依赖 DetailModuleAdapter，避免与具体模块耦合。
class UnifiedDetailPage extends StatefulWidget {
  const UnifiedDetailPage({
    super.key,
    required this.adapter,
    required this.workId,
    required this.onOpenReader,
    required this.onOpenThread,
  });

  final DetailModuleAdapter adapter;
  final String workId;
  final Future<void> Function(BuildContext context, ReaderRouteTarget target) onOpenReader;
  final Future<void> Function(BuildContext context, ThreadRouteTarget target) onOpenThread;

  @override
  State<UnifiedDetailPage> createState() => _UnifiedDetailPageState();
}

class _UnifiedDetailPageState extends State<UnifiedDetailPage> {
  static const double _collapsedTitleRevealOffset = 170;

  late final UnifiedDetailController _controller;
  late final ScrollController _scrollController;

  bool _introExpanded = false;
  bool _showCollapsedTitle = false;

  @override
  void initState() {
    super.initState();
    _controller = UnifiedDetailController(
      adapter: widget.adapter,
      workId: widget.workId,
    );
    _scrollController = ScrollController()..addListener(_handleScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _controller.initialize();
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    final shouldShow = _scrollController.hasClients &&
        _scrollController.offset >= _collapsedTitleRevealOffset;
    if (shouldShow != _showCollapsedTitle && mounted) {
      setState(() => _showCollapsedTitle = shouldShow);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageContext = this.context;
    final state = _controller.state;
    final header = state.header;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: _showCollapsedTitle
            ? Theme.of(context).colorScheme.surface
            : Colors.transparent,
        forceMaterialTransparency: !_showCollapsedTitle,
        elevation: _showCollapsedTitle ? 1 : 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(
          color: _showCollapsedTitle
              ? Theme.of(context).colorScheme.onSurface
              : Colors.white,
        ),
        title: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _showCollapsedTitle ? 1 : 0,
          child: Text(
            header?.title ?? '',
            key: const Key('unified-detail-collapsed-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '下载',
            icon: const Icon(Icons.file_download),
            onSelected: (value) async {
              if (value == 'download-unread') {
                await widget.adapter.downloadUnread(workId: widget.workId);
              } else if (value == 'download-all') {
                await widget.adapter.downloadAll(workId: widget.workId);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'download-unread', child: Text('未读')),
              PopupMenuItem(value: 'download-all', child: Text('全部')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // Phase 5 继续实现章节筛选细节。
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'refresh', child: Text('刷新')),
              PopupMenuItem(value: 'edit-intro', child: Text('编辑简介')),
            ],
            onSelected: (value) async {
              if (value == 'refresh') {
                await _controller.refresh();
                if (!mounted) {
                  return;
                }
                setState(() {});
              }
            },
          ),
        ],
      ),
      body: state.isLoading && header == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              // 从屏幕顶部出现刷新指示器。
              edgeOffset: 0,
              displacement: 28,
              elevation: 0,
              onRefresh: () async {
                await _controller.refresh();
                if (!mounted) {
                  return;
                }
                setState(() {});
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                slivers: [
                  if (header != null)
                    SliverToBoxAdapter(
                      child: _HeroInfoSection(
                        header: header,
                        moduleKey: widget.adapter.moduleKey,
                        topInset: topInset,
                      ),
                    ),
                  if (header != null)
                    SliverToBoxAdapter(
                      child: _HeaderActionsRow(
                        header: header,
                        onToggleShelf: () {},
                        onRefresh: () async {
                          await _controller.refresh();
                          if (!mounted) {
                            return;
                          }
                          setState(() {});
                        },
                        onOpenThread: () async {
                          final target = await widget.adapter.getThreadRouteTarget(workId: widget.workId);
                          if (!mounted || !pageContext.mounted || target == null) {
                            return;
                          }
                          await widget.onOpenThread(pageContext, target);
                        },
                      ),
                    ),
                  if (state.errorMessage != null && state.errorMessage!.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                        child: Text(
                          '加载失败：${state.errorMessage}',
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ),
                  if (header != null)
                    SliverToBoxAdapter(
                      child: _IntroSection(
                        intro: header.intro?.trim().isNotEmpty == true ? header.intro! : '暂无简介',
                        expanded: _introExpanded,
                        onToggle: () => setState(() => _introExpanded = !_introExpanded),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        '共 ${state.chapters.length} 章',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: state.chapters.length,
                    itemBuilder: (context, index) {
                      final chapter = state.chapters[index];
                      return ListTile(
                        key: ValueKey<String>('unified-detail-chapter-${chapter.episodeId}'),
                        title: Text(chapter.title),
                        subtitle: Text(
                          '${chapter.publishTimeText ?? '-'}  Tid:${chapter.sourceTid ?? '-'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          chapter.isDownloaded ? Icons.check_circle_outline : Icons.arrow_circle_down,
                        ),
                        onTap: () async {
                          final target = await widget.adapter.getReaderRouteTarget(
                            workId: widget.workId,
                            preferContinue: false,
                          );
                          if (!mounted || !pageContext.mounted || target == null) {
                            return;
                          }
                          await widget.onOpenReader(pageContext, target);
                        },
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final target = await widget.adapter.getReaderRouteTarget(
            workId: widget.workId,
            preferContinue: true,
          );
          if (!mounted || !pageContext.mounted || target == null) {
            return;
          }
          await widget.onOpenReader(pageContext, target);
        },
        icon: const Icon(Icons.play_arrow),
        label: const Text('继续'),
      ),
    );
  }
}

/// 可随列表滚动消失的封面+元信息区。
class _HeroInfoSection extends StatelessWidget {
  const _HeroInfoSection({
    required this.header,
    required this.moduleKey,
    required this.topInset,
  });

  // Hero 区高度（含状态栏与 AppBar 覆盖区）
  // 需要容纳：封面(168) + 元信息区 + 操作区，过小会导致底部溢出。
  static const double _heroExtraHeight = 240;
  // 封面与文字块的内边距
  static const EdgeInsets _contentPadding = EdgeInsets.fromLTRB(30, 0, 12, 30);

  final LibraryDetailHeader header;
  final LibraryModuleKey moduleKey;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final title = header.title;
    final author = header.author?.trim().isNotEmpty == true ? header.author! : '未知作者';
    final group =
        header.translationGroup?.trim().isNotEmpty == true ? header.translationGroup! : '未知汉化组';

    return SizedBox(
      height: topInset + kToolbarHeight + _heroExtraHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _DetailHeaderBackground(
            title: title,
            coverImageUrl: header.coverImageUrl,
            hasCover: header.coverImageUrl?.trim().isNotEmpty == true,
          ),
          Padding(
            padding: _contentPadding.copyWith(top: topInset + kToolbarHeight + 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _CoverImage(url: header.coverImageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    // 文字区底边距不要过大，否则会形成“被拉开”的视觉缝隙。
                    padding: const EdgeInsets.only(top: 6, left: 0, right: 0, bottom: 30),
                    child: _HeroMetaColumn(
                      moduleKey: moduleKey,
                      title: title,
                      author: author,
                      translationGroup: group,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 底部收口带：强制与页面背景同色，消除分界线。
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context).colorScheme.surface.withAlpha(0),
                    Theme.of(context).colorScheme.surface,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetaColumn extends StatelessWidget {
  const _HeroMetaColumn({
    required this.moduleKey,
    required this.title,
    required this.author,
    required this.translationGroup,
  });

  final LibraryModuleKey moduleKey;
  final String title;
  final String author;
  final String translationGroup;

  @override
  Widget build(BuildContext context) {
    final groupLabel = moduleKey == LibraryModuleKey.comic ? translationGroup : '原作者作品';

    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Colors.white),
      child: Column(
        key: const Key('unified-detail-hero-meta'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            key: const Key('unified-detail-hero-title'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            key: const Key('unified-detail-author-row'),
            children: [
              const Icon(Icons.person_outlined, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            key: const Key('unified-detail-group-row'),
            children: [
              const Icon(Icons.group_outlined, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  groupLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailHeaderBackground extends StatelessWidget {
  const _DetailHeaderBackground({
    required this.title,
    required this.coverImageUrl,
    required this.hasCover,
  });

  // 可统一调节模糊强度；你觉得偏糊就继续往下调。
  static const double _blurSigma = 6;

  final String title;
  final String? coverImageUrl;
  final bool hasCover;

  @override
  Widget build(BuildContext context) {
    if (!hasCover) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 仅对背景图本身做模糊，避免把滚动中的列表内容一起模糊。
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
            child: Image.network(
              coverImageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(color: Theme.of(context).colorScheme.surfaceContainerHighest);
              },
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withAlpha(35),
                Theme.of(context).colorScheme.surface.withAlpha(150),
                Theme.of(context).colorScheme.surface,
              ],
              // 最后一段必须落到纯 surface，避免底部出现“线”。
              stops: const [0.0, 0.72, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderActionsRow extends StatelessWidget {
  const _HeaderActionsRow({
    required this.header,
    required this.onToggleShelf,
    required this.onRefresh,
    required this.onOpenThread,
  });

  final LibraryDetailHeader header;
  final VoidCallback onToggleShelf;
  final VoidCallback onRefresh;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 顶部边界不留白，避免下拉时出现“被拉开”的缝隙感。
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: _ActionChip(
            icon: header.inShelf ? Icons.favorite : Icons.favorite_border,
            label: header.inShelf ? '在书架中' : '添加到书架',
            onTap: onToggleShelf,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionChip(icon: Icons.refresh, label: '更新', onTap: onRefresh),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionChip(icon: Icons.open_in_new, label: '原帖', onTap: onOpenThread),
          ),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 120,
        height: 168,
        child: url == null || url!.trim().isEmpty
            ? Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.image_not_supported_outlined),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroSection extends StatelessWidget {
  const _IntroSection({
    required this.intro,
    required this.expanded,
    required this.onToggle,
  });

  final String intro;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('简介', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onToggle,
            child: Text(
              intro,
              maxLines: expanded ? null : 3,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            expanded ? '收起' : '展开',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    );
  }
}
