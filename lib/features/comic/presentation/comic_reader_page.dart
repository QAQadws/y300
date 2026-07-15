import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/comic/domain/models/comic_reader_exit_result.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_unavailable.dart';
import 'package:y300/features/comic/presentation/comic_reader_capability.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/library_shared/presentation/widgets/cover_focal_point_picker.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/reader_shared/presentation/reader_preferences/reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

enum _ComicReaderMoreAction { markReadToggle, setCurrentPageAsCover }

/// 漫画阅读器页面。
///
/// 通用阅读壳（模式/缩放/overlay/滑块/页码/显示设置/滚动锚定）已下沉到
/// [ImageReaderEngine]；本页只负责漫画专属编排：加载/错误态、章节切换、更多操作、
/// 章节列表、原帖跳转、下一章过场卡，并通过 [ComicReaderCapability] 注入引擎。
class ComicReaderPage extends ConsumerStatefulWidget {
  const ComicReaderPage({
    super.key,
    required this.comicId,
    required this.episodeId,
    this.diagnosticRecorder = const NoopContinuousImageDiagnosticRecorder(),
  });

  final String comicId;
  final String episodeId;
  final ContinuousImageDiagnosticRecorder diagnosticRecorder;

  @override
  ConsumerState<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends ConsumerState<ComicReaderPage> {
  ComicReaderArgs get _readerArgs =>
      ComicReaderArgs(comicId: widget.comicId, episodeId: widget.episodeId);

  ComicReaderController _controller() {
    return ref.read(comicReaderControllerProvider(_readerArgs).notifier);
  }

  @override
  Widget build(BuildContext context) {
    final preferencesState = ref.watch(readerPreferencesControllerProvider);
    final preferences = preferencesState.value ?? ReaderPreferences.defaults();
    final state = ref.watch(comicReaderControllerProvider(_readerArgs));
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);

    return Scaffold(
      body: state.when(
        loading: () => _ReaderOpeningPlaceholder(
          background: _readerBackgroundColor(preferences),
        ),
        error: (error, stackTrace) => _buildReaderErrorState(error),
        data: (viewState) {
          if (viewState.images.isEmpty) {
            return const Center(child: Text('当前章节没有可阅读图片'));
          }
          final controller = _controller();
          return ImageReaderEngine(
            key: const Key('comic-reader-engine'),
            listKey: const Key('comic-reader-image-list'),
            pageKey: const Key('comic-reader-page-view'),
            slotKeyPrefix: 'comic-reader-image-slot',
            capability: ComicReaderCapability(
              viewState: viewState,
              preferences: preferences,
              imageHeaderBuilder: imageHeaderBuilder,
              controller: controller,
              diagnosticRecorder: widget.diagnosticRecorder,
              exitResult: _exitResultFor(viewState),
              onToggleBookmark: () => unawaited(_toggleBookmark()),
              onOpenSourceThread: () => _openSourceThread(viewState),
              onShowMoreActions: () =>
                  unawaited(_showMoreActionSheet(viewState)),
              onShowChapterList: () =>
                  unawaited(_showChapterListSheet(viewState)),
              onOpenAdjacentEpisode: ({required bool previous}) => unawaited(
                _openAdjacentEpisode(viewState, previous: previous),
              ),
              buildNextChapterTransition: (context) =>
                  _ReaderNextChapterTransition(
                    nextChapter: viewState.nextChapter,
                    isSwitchingEpisode: viewState.isSwitchingEpisode,
                    onOpenNext: () => unawaited(
                      _openAdjacentEpisode(viewState, previous: false),
                    ),
                  ),
            ),
          );
        },
      ),
    );
  }
  // COMIC_PAGE_BODY_PLACEHOLDER

  /// 阅读器错误态：拉单话图片失败显示根因 + 重试；解析失败不出重试按钮。
  Widget _buildReaderErrorState(Object error) {
    final hint = error is ComicEpisodeImagesUnavailable
        ? error.displayHint
        : '加载阅读器失败：$error';
    final retryable =
        error is! ComicEpisodeImagesUnavailable || error.isRetryable;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hint, textAlign: TextAlign.center),
            if (retryable) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    ref.invalidate(comicReaderControllerProvider(_readerArgs)),
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  ComicReaderExitResult _exitResultFor(ComicReaderViewState viewState) {
    return ComicReaderExitResult(
      comicId: viewState.comicId,
      lastReadEpisodeId: viewState.episodeId,
      completedEpisodeIds: viewState.isCurrentEpisodeRead
          ? <String>[viewState.episodeId]
          : const <String>[],
    );
  }

  Color _readerBackgroundColor(ReaderPreferences preferences) {
    final scheme = Theme.of(context).colorScheme;
    switch (preferences.background) {
      case ReaderBackgroundPreference.followTheme:
        return scheme.surface;
      case ReaderBackgroundPreference.black:
        return Colors.black;
      case ReaderBackgroundPreference.white:
        return Colors.white;
      case ReaderBackgroundPreference.gray:
        return const Color(0xFF202124);
    }
  }

  Future<void> _openSourceThread(ComicReaderViewState viewState) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(
          tid: viewState.sourceTid,
          subject: viewState.episodeTitle,
        ),
      ),
    );
  }

  Future<void> _openAdjacentEpisode(
    ComicReaderViewState viewState, {
    required bool previous,
  }) async {
    if (viewState.isSwitchingEpisode) {
      return;
    }
    final controller = _controller();
    final targetEpisodeId = previous
        ? await controller.goToPreviousEpisode()
        : await controller.goToNextEpisode();
    if (targetEpisodeId == null || !mounted) {
      return;
    }
    // 引擎按 ownerId（episodeId）变化自动复位滚动/索引，这里无需手动重置位置。
    await controller.goToEpisode(targetEpisodeId);
  }

  Future<void> _handleReaderMoreAction(
    _ComicReaderMoreAction action,
    ComicReaderViewState viewState,
  ) async {
    final controller = _controller();
    switch (action) {
      case _ComicReaderMoreAction.markReadToggle:
        final message = await controller.setCurrentEpisodeRead(
          !viewState.isCurrentEpisodeRead,
        );
        if (mounted && message != null) {
          showTransientSnackBar(context, message);
        }
      case _ComicReaderMoreAction.setCurrentPageAsCover:
        await _handleSetCoverWithFocus();
    }
  }

  Future<void> _toggleBookmark() async {
    final message = await _controller().toggleBookmark();
    if (mounted && message != null) {
      showTransientSnackBar(context, message);
    }
  }

  /// 设当前页为封面：先落盘取本地文件，弹出焦点选区器让用户取景，再保存焦点。
  Future<void> _handleSetCoverWithFocus() async {
    final controller = _controller();
    final localPath = await controller.prepareCurrentImageForCover();
    if (localPath == null || localPath.trim().isEmpty || !mounted) {
      if (mounted) {
        showTransientSnackBar(context, '当前页图片缓存失败，无法设为封面');
      }
      return;
    }
    final focus = await CoverFocalPointPicker.show(
      context,
      image: FileImage(io.File(localPath)),
      title: '调整封面焦点',
    );
    if (focus == null || !mounted) {
      // 取消选区则不改动封面。
      return;
    }
    final message = await controller.setCurrentImageAsCover(
      focusX: focus.x,
      focusY: focus.y,
    );
    if (mounted && message != null) {
      showTransientSnackBar(context, message);
    }
  }

  Future<void> _showMoreActionSheet(ComicReaderViewState viewState) async {
    final action = await showModalBottomSheet<_ComicReaderMoreAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => ReaderActionSheet<_ComicReaderMoreAction>(
        title: '更多操作',
        items: [
          ReaderActionSheetItem<_ComicReaderMoreAction>(
            id: 'mark-read-toggle',
            value: _ComicReaderMoreAction.markReadToggle,
            icon: viewState.isCurrentEpisodeRead
                ? Icons.radio_button_unchecked
                : Icons.check_circle_outline,
            label: viewState.isCurrentEpisodeRead ? '标记本章未读' : '标记本章已读',
          ),
          const ReaderActionSheetItem<_ComicReaderMoreAction>(
            id: 'set-cover',
            value: _ComicReaderMoreAction.setCurrentPageAsCover,
            icon: Icons.image_outlined,
            label: '将当前页设为封面',
          ),
        ],
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    await _handleReaderMoreAction(action, viewState);
  }

  Future<void> _showChapterListSheet(ComicReaderViewState viewState) async {
    final selected = await showModalBottomSheet<ComicReaderChapterEntry>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ReaderSheetTitle(title: '章节列表'),
            for (final chapter in viewState.chapters)
              ListTile(
                key: ValueKey<String>(
                  'comic-reader-chapter-${chapter.episodeId}',
                ),
                selected: chapter.isCurrent,
                leading: Icon(
                  chapter.isRead
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                ),
                title: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: chapter.isCurrent ? const Text('当前') : null,
                onTap: () => Navigator.of(context).pop(chapter),
              ),
          ],
        ),
      ),
    );
    if (selected == null || selected.isCurrent || !mounted) {
      return;
    }
    await _controller().goToEpisode(selected.episodeId);
  }
}

/// 垂直模式列表尾部的"下一章过场卡"。只展示已加载的章节元数据；图片列表和
/// owner session 均在用户确认切换后创建。
class _ReaderNextChapterTransition extends StatelessWidget {
  const _ReaderNextChapterTransition({
    required this.nextChapter,
    required this.isSwitchingEpisode,
    required this.onOpenNext,
  });

  final ComicReaderChapterEntry? nextChapter;
  final bool isSwitchingEpisode;
  final VoidCallback onOpenNext;

  @override
  Widget build(BuildContext context) {
    final chapter = nextChapter;
    if (chapter == null) {
      return const SizedBox.shrink(
        key: Key('comic-reader-next-chapter-transition-empty'),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chromePalette = const ReaderChromePaletteResolver().resolve(theme);
    final canOpen = !isSwitchingEpisode;
    return Padding(
      key: const Key('comic-reader-next-chapter-transition'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 56),
      child: Material(
        color: chromePalette.transitionCardBackground,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: const Key('comic-reader-next-chapter-transition-button'),
          borderRadius: BorderRadius.circular(8),
          onTap: canOpen ? onOpenNext : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.skip_next, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '下一章：${chapter.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isSwitchingEpisode ? '正在切换章节' : '点击进入下一章',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isSwitchingEpisode)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.chevron_right,
                    color: canOpen ? scheme.primary : scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 章节打开中的占位：短暂延迟后再显示文案，避免一闪而过的页级占位。
class _ReaderOpeningPlaceholder extends StatefulWidget {
  const _ReaderOpeningPlaceholder({required this.background});

  final Color background;

  @override
  State<_ReaderOpeningPlaceholder> createState() =>
      _ReaderOpeningPlaceholderState();
}

class _ReaderOpeningPlaceholderState extends State<_ReaderOpeningPlaceholder> {
  static const Duration _revealDelay = Duration(milliseconds: 160);

  Timer? _timer;
  bool _showCopy = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_revealDelay, () {
      if (!mounted) {
        return;
      }
      setState(() => _showCopy = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('comic-reader-page-opening'),
      color: widget.background,
      child: Center(
        child: _showCopy
            ? Text('正在打开章节', style: Theme.of(context).textTheme.bodySmall)
            : const SizedBox.shrink(),
      ),
    );
  }
}
