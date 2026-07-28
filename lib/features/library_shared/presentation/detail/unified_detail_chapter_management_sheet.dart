import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/presentation/services/library_detail_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

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
        final l10n = AppLocalizations.of(context);
        setState(() {
          _loading = false;
          _loadError = l10n.libraryChapterLoadFailed(
            LibraryDetailTextResolver.safeError(l10n, error),
          );
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
    final l10n = AppLocalizations.of(context);
    final manualCount = _chapters.where((item) => item.isManual).length;
    final hiddenCount = _chapters.where((item) => item.isHidden).length;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.libraryDetailManageChapters,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                _loading
                    ? l10n.libraryChapterManagementLoading
                    : l10n.libraryChapterManagementSummary(
                        _chapters.length,
                        _chapters.length - manualCount,
                        manualCount,
                        hiddenCount,
                      ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: l10n.commonClose,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    final l10n = AppLocalizations.of(context);
    return TextField(
      key: const Key('unified-detail-chapter-management-search'),
      controller: _searchController,
      enabled: !_loading && _loadError == null,
      onChanged: (value) => setState(() => _searchQuery = value.trim()),
      decoration: InputDecoration(
        labelText: l10n.libraryChapterFilterLabel,
        hintText: l10n.libraryChapterFilterHint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: l10n.libraryChapterClearFilter,
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
    final l10n = AppLocalizations.of(context);
    return TextField(
      key: const Key('unified-detail-chapter-management-input'),
      controller: _inputController,
      enabled: !_adding,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: l10n.libraryChapterAdd,
        hintText: l10n.libraryChapterAddHint,
        helperText: l10n.libraryChapterAddHelp,
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
                tooltip: l10n.libraryChapterAdd,
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
    final l10n = AppLocalizations.of(context);
    final canBulk = !_loading && _chapters.isNotEmpty && !_bulkBusy;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('unified-detail-chapter-management-show-all'),
            onPressed: canBulk ? () => _setAllHidden(false) : null,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(l10n.libraryChapterShowAll),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('unified-detail-chapter-management-hide-all'),
            onPressed: canBulk ? () => _setAllHidden(true) : null,
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: Text(l10n.libraryChapterHideAll),
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
            AppLocalizations.of(context).libraryChapterManagementEmpty,
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
          AppLocalizations.of(context).libraryChapterManagementNoMatches,
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
    final l10n = AppLocalizations.of(context);
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
        tooltip: chapter.isHidden
            ? l10n.libraryChapterShow
            : l10n.libraryChapterHide,
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
        LibraryDetailTextResolver.chapterTitle(
          l10n,
          chapter.title,
          chapter.sourceTid,
        ),
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
                'Tid:${chapter.sourceTid}'
                '${chapter.isHidden ? ' · ${l10n.libraryChapterHidden}' : ''}',
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
      // 重命名对两种来源都开放；移除仍然只给手动章节。
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: ValueKey<String>(
                    'unified-detail-chapter-management-rename-${chapter.episodeId}',
                  ),
                  tooltip: l10n.libraryChapterRename,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _bulkBusy ? null : () => _promptRename(chapter),
                ),
                if (chapter.isManual)
                  IconButton(
                    key: ValueKey<String>(
                      'unified-detail-chapter-management-remove-${chapter.episodeId}',
                    ),
                    tooltip: l10n.libraryChapterRemove,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _bulkBusy ? null : () => _confirmRemove(chapter),
                  ),
              ],
            ),
    );
  }

  Future<void> _addChapter() async {
    final input = _inputController.text.trim();
    setState(() {
      _adding = true;
      _inputError = null;
    });
    try {
      final outcome = await widget.adapter.addManualChapter(
        workId: widget.workId,
        input: input,
      );
      if (!mounted) {
        return;
      }
      if (outcome.code == DetailManualChapterAddOutcomeCode.duplicate) {
        setState(() {
          _inputError = AppLocalizations.of(context).libraryChapterDuplicate;
        });
        return;
      }
      if (outcome.code == DetailManualChapterAddOutcomeCode.invalidInput) {
        setState(() {
          _inputError = LibraryDetailTextResolver.manualChapterInputError(
            AppLocalizations.of(context),
            outcome,
          );
        });
        return;
      }
      _inputController.clear();
      _notifyChanged();
      await _load();
      if (mounted) {
        _showMessage(AppLocalizations.of(context).libraryChapterAdded);
      }
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _inputError = l10n.libraryChapterAddFailed(
            LibraryDetailTextResolver.safeError(l10n, error),
          );
        });
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
                      sourceTitle: item.sourceTitle,
                      customTitle: item.customTitle,
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
        final l10n = AppLocalizations.of(context);
        _showMessage(
          l10n.libraryChapterVisibilityUpdateFailed(
            LibraryDetailTextResolver.safeError(l10n, error),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyEpisodeIds.remove(chapter.episodeId));
      }
    }
  }

  Future<void> _promptRename(DetailManagedChapter chapter) async {
    // 取消与「清空以恢复来源名」都会得到空标题，用包装对象区分二者：
    // 返回 null = 用户取消，返回对象且 customTitle 为 null = 用户要求恢复。
    final result = await showDialog<_ChapterRenameResult>(
      context: context,
      builder: (dialogContext) => _ChapterRenameDialog(
        chapter: chapter,
        initialTitle: LibraryDetailTextResolver.chapterTitle(
          AppLocalizations.of(dialogContext),
          chapter.title,
          chapter.sourceTid,
        ),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() => _busyEpisodeIds.add(chapter.episodeId));
    try {
      await widget.adapter.renameChapter(
        workId: widget.workId,
        episodeId: chapter.episodeId,
        customTitle: result.customTitle,
      );
      _notifyChanged();
      // 重命名后的展示名由存储层按 custom/source 规则算出，这里重新读回而不是
      // 在内存里拼一遍，避免面板和数据库对“该显示哪个名字”产生两套口径。
      await _load();
      if (mounted) {
        _showMessage(
          result.customTitle == null
              ? AppLocalizations.of(context).libraryChapterRestoredSourceTitle
              : AppLocalizations.of(context).libraryChapterRenamed,
        );
      }
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        _showMessage(
          l10n.libraryChapterRenameFailed(
            LibraryDetailTextResolver.safeError(l10n, error),
          ),
        );
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
        _showMessage(
          isHidden
              ? AppLocalizations.of(context).libraryChapterAllHidden
              : AppLocalizations.of(context).libraryChapterAllShown,
        );
      }
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        _showMessage(
          l10n.libraryChapterBulkUpdateFailed(
            LibraryDetailTextResolver.safeError(l10n, error),
          ),
        );
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
          title: Text(
            AppLocalizations.of(dialogContext).libraryChapterRemoveTitle,
          ),
          content: Text(
            AppLocalizations.of(dialogContext).libraryChapterRemoveBody(
              LibraryDetailTextResolver.chapterTitle(
                AppLocalizations.of(dialogContext),
                chapter.title,
                chapter.sourceTid,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppLocalizations.of(dialogContext).commonCancel),
            ),
            FilledButton(
              key: const Key(
                'unified-detail-chapter-management-remove-confirm',
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(AppLocalizations.of(dialogContext).commonRemove),
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
        _showMessage(
          LibraryDetailTextResolver.chapterRemovalOutcome(
            AppLocalizations.of(context),
            result,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        _showMessage(
          l10n.libraryChapterRemoveFailed(
            LibraryDetailTextResolver.safeError(l10n, error),
          ),
        );
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

/// 重命名结果。存在实例即表示用户点了保存；[customTitle] 为 null 表示恢复来源名。
class _ChapterRenameResult {
  const _ChapterRenameResult(this.customTitle);

  final String? customTitle;
}

/// 章节重命名弹窗。
///
/// 与「编辑作品信息」同一套交互：输入框回填当前展示名，helper 说明清空后会
/// 退回哪个来源名，因此“改名”和“还原”共用一个输入框，不需要额外的还原按钮。
class _ChapterRenameDialog extends StatefulWidget {
  const _ChapterRenameDialog({
    required this.chapter,
    required this.initialTitle,
  });

  final DetailManagedChapter chapter;
  final String initialTitle;

  @override
  State<_ChapterRenameDialog> createState() => _ChapterRenameDialogState();
}

class _ChapterRenameDialogState extends State<_ChapterRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // 回填展示名而不是只回填自定义名：未改名的章节也应该能在原名上小改，
    // 而不是面对一个空输入框重新打字。
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sourceTitle = widget.chapter.sourceTitle;
    return AlertDialog(
      title: Text(l10n.libraryChapterRenameTitle),
      content: TextField(
        key: const Key('unified-detail-chapter-management-rename-input'),
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: l10n.libraryChapterName,
          helperText: sourceTitle == null
              ? l10n.libraryChapterRestoreDefaultTitleHelp
              : l10n.libraryChapterRestoreSourceTitleHelp(sourceTitle),
          helperMaxLines: 3,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('unified-detail-chapter-management-rename-confirm'),
          onPressed: _submit,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    // 原样保存回填的来源名不该被记成自定义名，否则来源以后改名了也再也跟不上。
    // 与「配置目录」的 `normalized == source ? null : normalized` 同一套约定。
    final custom = trimmed.isEmpty || trimmed == widget.chapter.sourceTitle
        ? null
        : trimmed;
    Navigator.of(context).pop(_ChapterRenameResult(custom));
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
        isManual
            ? AppLocalizations.of(context).libraryChapterManual
            : AppLocalizations.of(context).libraryChapterParsed,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
