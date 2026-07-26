import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';

/// 章节管理面板。
///
/// 解析章节与手动章节合在一个列表里：用户关心的是“这部作品有哪些章节”，
/// 按来源拆成两段会让阅读顺序断裂。来源差异改用行内标签和可用动作表达——
/// 解析章节只能隐藏（下次刷新还会回来，给出“移除”是假承诺），手动章节可移除。
class UnifiedDetailChapterManagementSheet extends StatefulWidget {
  const UnifiedDetailChapterManagementSheet({
    super.key,
    required this.workId,
    required this.adapter,
    this.onChanged,
  });

  final String workId;
  final DetailChapterManagementAdapter adapter;

  /// 每次成功写入后回调。面板可能被点击遮罩关闭，用回调而不是返回值通知外层，
  /// 才能保证详情页一定知道要重新加载。
  final VoidCallback? onChanged;

  @override
  State<UnifiedDetailChapterManagementSheet> createState() =>
      _UnifiedDetailChapterManagementSheetState();
}

class _UnifiedDetailChapterManagementSheetState
    extends State<UnifiedDetailChapterManagementSheet> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _busyEpisodeIds = <String>{};

  List<DetailManagedChapter> _chapters = const <DetailManagedChapter>[];
  bool _loading = true;
  bool _adding = false;
  bool _bulkBusy = false;
  String? _inputError;
  String? _loadError;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final chapters = await widget.adapter.loadManagedChapters(
        workId: widget.workId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _chapters = chapters;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '读取章节失败：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      key: const Key('unified-detail-chapter-management-draggable-sheet'),
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.42,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Material(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
              ),
              child: Column(
                key: const Key('unified-detail-chapter-management-sheet'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 12),
                  _buildAddField(),
                  const SizedBox(height: 8),
                  _buildSearchField(),
                  const SizedBox(height: 12),
                  _buildBulkActions(),
                  const Divider(height: 20),
                  Expanded(child: _buildBody(theme, scrollController)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final manualCount = _chapters.where((item) => item.isManual).length;
    final hiddenCount = _chapters.where((item) => item.isHidden).length;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('管理章节', style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                _loading
                    ? '正在读取…'
                    : '共 ${_chapters.length} 章 · 解析 ${_chapters.length - manualCount} · 手动 $manualCount · 已隐藏 $hiddenCount',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      key: const Key('unified-detail-chapter-management-search'),
      controller: _searchController,
      enabled: !_loading && _loadError == null,
      onChanged: (value) => setState(() => _searchQuery = value.trim()),
      decoration: InputDecoration(
        labelText: '筛选章节',
        hintText: '按标题或 TID 搜索',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: '清除筛选',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        isDense: true,
      ),
    );
  }

  Widget _buildAddField() {
    return TextField(
      key: const Key('unified-detail-chapter-management-input'),
      controller: _inputController,
      enabled: !_adding,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: '添加章节',
        hintText: '粘贴帖子链接或直接输入 tid',
        helperText: '支持 forum.php、thread-xxx.html、api/mobile 等链接形态',
        helperMaxLines: 2,
        errorText: _inputError,
        errorMaxLines: 3,
        isDense: true,
        suffixIcon: _adding
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                key: const Key('unified-detail-chapter-management-add'),
                tooltip: '添加',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _addChapter,
              ),
      ),
      onSubmitted: (_) {
        if (!_adding) {
          _addChapter();
        }
      },
    );
  }

  Widget _buildBulkActions() {
    final canBulk = !_loading && _chapters.isNotEmpty && !_bulkBusy;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('unified-detail-chapter-management-show-all'),
            onPressed: canBulk ? () => _setAllHidden(false) : null,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('全部显示'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('unified-detail-chapter-management-hide-all'),
            onPressed: canBulk ? () => _setAllHidden(true) : null,
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: const Text('全部隐藏'),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(ThemeData theme, ScrollController scrollController) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final loadError = _loadError;
    if (loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            loadError,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }
    if (_chapters.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '暂无章节，可在上方粘贴帖子链接手动添加',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final query = _searchQuery.toLowerCase();
    final chapters = query.isEmpty
        ? _chapters
        : _chapters
              .where(
                (chapter) =>
                    chapter.title.toLowerCase().contains(query) ||
                    chapter.sourceTid.toLowerCase().contains(query),
              )
              .toList(growable: false);
    if (chapters.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的章节',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: EdgeInsets.zero,
      itemCount: chapters.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildChapterRow(theme, chapters[index]),
    );
  }

  Widget _buildChapterRow(ThemeData theme, DetailManagedChapter chapter) {
    final busy = _busyEpisodeIds.contains(chapter.episodeId);
    final dimmed = chapter.isHidden;
    final titleColor = dimmed
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;
    return ListTile(
      key: ValueKey<String>(
        'unified-detail-chapter-management-row-${chapter.episodeId}',
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      // 隐藏状态用行首图标而不是行尾开关：用户扫这一列就能看出哪些章节不显示。
      leading: IconButton(
        key: ValueKey<String>(
          'unified-detail-chapter-management-visibility-${chapter.episodeId}',
        ),
        tooltip: chapter.isHidden ? '显示该章节' : '隐藏该章节',
        icon: Icon(
          chapter.isHidden
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          color: chapter.isHidden
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.primary,
        ),
        onPressed: busy || _bulkBusy
            ? null
            : () => _toggleHidden(chapter, !chapter.isHidden),
      ),
      title: Text(
        chapter.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(color: titleColor),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            _SourceBadge(isManual: chapter.isManual),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Tid:${chapter.sourceTid}${chapter.isHidden ? ' · 已隐藏' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : chapter.isManual
          ? IconButton(
              key: ValueKey<String>(
                'unified-detail-chapter-management-remove-${chapter.episodeId}',
              ),
              tooltip: '移除该章节',
              icon: const Icon(Icons.delete_outline),
              onPressed: _bulkBusy ? null : () => _confirmRemove(chapter),
            )
          : null,
    );
  }

  Future<void> _addChapter() async {
    final input = _inputController.text.trim();
    setState(() {
      _adding = true;
      _inputError = null;
    });
    try {
      final added = await widget.adapter.addManualChapter(
        workId: widget.workId,
        input: input,
      );
      if (!mounted) {
        return;
      }
      if (!added) {
        setState(() => _inputError = '该章节已存在');
        return;
      }
      _inputController.clear();
      _notifyChanged();
      await _load();
      if (mounted) {
        _showMessage('已添加章节');
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _inputError = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _inputError = '添加失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  Future<void> _toggleHidden(
    DetailManagedChapter chapter,
    bool isHidden,
  ) async {
    setState(() => _busyEpisodeIds.add(chapter.episodeId));
    try {
      await widget.adapter.setChapterHidden(
        workId: widget.workId,
        episodeId: chapter.episodeId,
        isHidden: isHidden,
      );
      _notifyChanged();
      if (!mounted) {
        return;
      }
      // 只改内存里的这一行：整表重载会让列表跳动，用户连续切几个开关时很难受。
      setState(() {
        _chapters = _chapters
            .map(
              (item) => item.episodeId == chapter.episodeId
                  ? DetailManagedChapter(
                      episodeId: item.episodeId,
                      title: item.title,
                      sourceTid: item.sourceTid,
                      isManual: item.isManual,
                      isHidden: isHidden,
                    )
                  : item,
            )
            .toList(growable: false);
      });
    } catch (error) {
      if (mounted) {
        _showMessage('更新显示状态失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busyEpisodeIds.remove(chapter.episodeId));
      }
    }
  }

  Future<void> _setAllHidden(bool isHidden) async {
    setState(() => _bulkBusy = true);
    try {
      await widget.adapter.setAllChaptersHidden(
        workId: widget.workId,
        isHidden: isHidden,
      );
      _notifyChanged();
      await _load();
      if (mounted) {
        _showMessage(isHidden ? '已隐藏全部章节' : '已显示全部章节');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('批量更新失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _bulkBusy = false);
      }
    }
  }

  Future<void> _confirmRemove(DetailManagedChapter chapter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('移除该章节？'),
          content: Text('将删除手动添加的「${chapter.title}」及其阅读记录与下载任务，此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key(
                'unified-detail-chapter-management-remove-confirm',
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('移除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busyEpisodeIds.add(chapter.episodeId));
    try {
      final result = await widget.adapter.removeManualChapter(
        workId: widget.workId,
        episodeId: chapter.episodeId,
      );
      if (result.removed) {
        _notifyChanged();
      }
      await _load();
      if (mounted) {
        if (!result.removed) {
          _showMessage('解析章节不可移除，可改为隐藏');
        } else if (result.warning != null) {
          _showMessage('章节已移除，但${result.warning}');
        } else {
          _showMessage('已移除章节');
        }
      }
    } catch (error) {
      if (mounted) {
        _showMessage('移除失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busyEpisodeIds.remove(chapter.episodeId));
      }
    }
  }

  void _notifyChanged() => widget.onChanged?.call();

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 章节来源标签。
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.isManual});

  final bool isManual;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isManual
        ? scheme.tertiaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = isManual
        ? scheme.onTertiaryContainer
        : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isManual ? '手动' : '解析',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
