import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/widgets/reader_style_panel.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

class NovelReaderPage extends ConsumerStatefulWidget {
  const NovelReaderPage({
    super.key,
    required this.novelId,
    required this.initialEpisodeId,
  });

  final String novelId;
  final String initialEpisodeId;

  @override
  ConsumerState<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends ConsumerState<NovelReaderPage> {
  late final ScrollController _scrollController;
  late final ReaderOverlayController _overlayController;
  bool _hasRestoredOffset = false;
  bool _isProgrammaticScrollChange = false;

  NovelReaderArgs get _args =>
      NovelReaderArgs(novelId: widget.novelId, episodeId: widget.initialEpisodeId);

  @override
  void initState() {
    super.initState();
    _overlayController = ReaderOverlayController();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _overlayController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(novelReaderControllerProvider(_args));
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);

    return Scaffold(
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载阅读器失败：$error')),
        data: (viewState) {
          _restoreOffsetIfNeeded(viewState.currentOffset);

          final colors = _resolveColors(viewState.preferences.themeMode);
          return ColoredBox(
            color: colors.background,
            child: ReaderOverlayScaffold(
              controller: _overlayController,
              topBar: _buildTopBarConfig(viewState),
              bottomBar: _buildBottomBarConfig(viewState, controller),
              bottomSafeFraction: 0.18,
              child: _buildParagraphList(viewState, colors),
            ),
          );
        },
      ),
    );
  }

  ReaderTopBarConfig _buildTopBarConfig(NovelReaderViewState viewState) {
    return ReaderTopBarConfig(
      title: _novelTitle(viewState),
      subtitle: viewState.currentEpisode.episodeTitle,
      onBack: () => _popReader(),
      actions: [
        ReaderToolbarAction(
          id: 'bookmark',
          icon: Icons.bookmark_border,
          label: '书签',
          onPressed: () => _showPlaceholder('书签功能将在后续阶段接入'),
        ),
        ReaderToolbarAction(
          id: 'search',
          icon: Icons.search,
          label: '搜索',
          onPressed: () => _showPlaceholder('本章搜索将在后续阶段接入'),
        ),
        ReaderToolbarAction(
          id: 'open-thread',
          icon: Icons.open_in_new,
          label: '打开原帖',
          onPressed: () => _openSourceThread(viewState),
        ),
        ReaderToolbarAction(
          id: 'more',
          icon: Icons.more_vert,
          label: '更多',
          onPressed: () => _showPlaceholder('更多阅读操作将在后续阶段接入'),
        ),
      ],
    );
  }

  ReaderBottomBarConfig _buildBottomBarConfig(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) {
    final currentIndex = _currentEpisodeIndex(viewState);
    final total = viewState.episodes.isEmpty ? 1 : viewState.episodes.length;
    final current = currentIndex < 0 ? 1 : currentIndex + 1;
    return ReaderBottomBarConfig(
      progress: ReaderProgressConfig(
        current: current,
        total: total,
        previousEnabled: currentIndex > 0,
        nextEnabled: currentIndex >= 0 && currentIndex < viewState.episodes.length - 1,
        onPrevious: () => _switchToPreviousEpisode(controller),
        onNext: () => _switchToNextEpisode(controller),
        onChanged: (_) {},
        onChangeEnd: (value) => _openEpisodeBySlider(value, viewState, controller),
      ),
      actions: [
        ReaderToolbarAction(
          id: 'catalog',
          icon: Icons.format_list_bulleted,
          label: '目录',
          onPressed: () => _showChapterListSheet(viewState, controller),
        ),
        ReaderToolbarAction(
          id: 'display',
          icon: Icons.tune,
          label: '显示',
          onPressed: () => _showDisplaySettingsSheet(viewState, controller),
        ),
        ReaderToolbarAction(
          id: 'cache',
          icon: Icons.download_for_offline_outlined,
          label: '缓存',
          onPressed: () => _showPlaceholder('章节缓存将在后续阶段接入'),
        ),
        ReaderToolbarAction(
          id: 'mode',
          icon: Icons.view_stream_outlined,
          label: '模式',
          onPressed: () => _showPlaceholder('阅读模式将在后续阶段接入'),
        ),
      ],
    );
  }

  Widget _buildParagraphList(
    NovelReaderViewState viewState,
    _ReaderColors colors,
  ) {
    return ListView.separated(
      key: const Key('novel-reader-paragraph-list'),
      controller: _scrollController,
      padding: EdgeInsets.all(viewState.preferences.pagePadding),
      itemCount: viewState.currentContent.paragraphs.length,
      separatorBuilder: (context, index) => SizedBox(
        height: viewState.preferences.paragraphSpacing,
      ),
      itemBuilder: (context, index) {
        final paragraph = viewState.currentContent.paragraphs[index];
        return Text(
          paragraph,
          style: TextStyle(
            color: colors.foreground,
            fontSize: viewState.preferences.fontSize,
            height: viewState.preferences.lineHeight,
          ),
        );
      },
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_isProgrammaticScrollChange) {
      return;
    }
    _overlayController.hideMenu();
    ref
        .read(novelReaderControllerProvider(_args).notifier)
        .onScrollOffsetChanged(_scrollController.offset);
  }

  void _restoreOffsetIfNeeded(double offset) {
    if (_hasRestoredOffset || offset <= 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _hasRestoredOffset) {
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      _isProgrammaticScrollChange = true;
      try {
        _scrollController.jumpTo(offset.clamp(0, max));
      } finally {
        _isProgrammaticScrollChange = false;
      }
      _hasRestoredOffset = true;
    });
  }

  Future<void> _popReader() async {
    if (_scrollController.hasClients) {
      await ref
          .read(novelReaderControllerProvider(_args).notifier)
          .saveCurrentOffsetNow(_scrollController.offset);
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _switchToPreviousEpisode(NovelReaderController controller) async {
    await _openDifferentEpisode(() => controller.goToPreviousEpisode());
  }

  Future<void> _switchToNextEpisode(NovelReaderController controller) async {
    await _openDifferentEpisode(() => controller.goToNextEpisode());
  }

  Future<void> _openEpisodeBySlider(
    double value,
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) async {
    if (viewState.episodes.isEmpty) {
      return;
    }
    final index = value.round().clamp(0, viewState.episodes.length - 1).toInt();
    final episode = viewState.episodes[index];
    if (episode.episodeId == viewState.currentEpisode.episodeId) {
      return;
    }
    await _openDifferentEpisode(() => controller.openEpisode(episode.episodeId));
  }

  Future<void> _openDifferentEpisode(Future<void> Function() action) async {
    if (_scrollController.hasClients) {
      await ref
          .read(novelReaderControllerProvider(_args).notifier)
          .saveCurrentOffsetNow(_scrollController.offset);
    }
    _hasRestoredOffset = false;
    if (_scrollController.hasClients) {
      _isProgrammaticScrollChange = true;
      try {
        _scrollController.jumpTo(0);
      } finally {
        _isProgrammaticScrollChange = false;
      }
    }
    _overlayController.hideMenu();
    await action();
  }

  Future<void> _showChapterListSheet(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) async {
    final selected = await showModalBottomSheet<NovelEpisodeItem>(
      context: context,
      showDragHandle: true,
      builder: (context) => NovelReaderChapterListSheet(viewState: viewState),
    );
    if (selected == null || selected.episodeId == viewState.currentEpisode.episodeId) {
      return;
    }
    await _openDifferentEpisode(() => controller.openEpisode(selected.episodeId));
  }

  void _showDisplaySettingsSheet(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) {
    _overlayController.hideMenu();
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ReaderStylePanel(
            preferences: viewState.preferences,
            onPreferencesChanged: controller.updatePreferences,
          ),
        ),
      ),
    );
  }

  Future<void> _openSourceThread(NovelReaderViewState viewState) async {
    final tid = (viewState.novel?.sourceTid.trim().isNotEmpty == true)
        ? viewState.novel!.sourceTid
        : viewState.currentEpisode.sourceTid;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(tid: tid, subject: _novelTitle(viewState)),
      ),
    );
  }

  void _showPlaceholder(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _novelTitle(NovelReaderViewState viewState) {
    final title = viewState.novel?.title.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    final episodeTitle = viewState.currentEpisode.episodeTitle.trim();
    if (episodeTitle.isNotEmpty) {
      return episodeTitle;
    }
    return widget.novelId;
  }

  int _currentEpisodeIndex(NovelReaderViewState viewState) {
    return viewState.episodes.indexWhere(
      (episode) => episode.episodeId == viewState.currentEpisode.episodeId,
    );
  }

  _ReaderColors _resolveColors(String themeMode) {
    switch (themeMode) {
      case 'dark':
        return const _ReaderColors(
          background: Color(0xFF141414),
          foreground: Color(0xFFE9E9E9),
        );
      case 'sepia':
        return const _ReaderColors(
          background: Color(0xFFF4EAD7),
          foreground: Color(0xFF4C3A21),
        );
      case 'light':
      default:
        return const _ReaderColors(
          background: Color(0xFFFDFDFD),
          foreground: Color(0xFF1F1F1F),
        );
    }
  }
}

class NovelReaderChapterListSheet extends StatelessWidget {
  const NovelReaderChapterListSheet({
    super.key,
    required this.viewState,
  });

  final NovelReaderViewState viewState;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: ListView(
          key: const Key('novel-reader-chapter-list-sheet'),
          shrinkWrap: true,
          children: [
            ReaderSheetTitle(title: '目录'),
            for (final episode in viewState.episodes)
              ListTile(
                key: Key('novel-reader-chapter-${episode.episodeId}'),
                selected: episode.episodeId == viewState.currentEpisode.episodeId,
                leading: Icon(
                  episode.episodeId == viewState.currentEpisode.episodeId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(
                  episode.episodeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: episode.datelineText == null
                    ? null
                    : Text(
                        episode.datelineText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: episode.episodeId == viewState.currentEpisode.episodeId
                    ? const Text('当前')
                    : null,
                onTap: () => Navigator.of(context).pop(episode),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReaderColors {
  const _ReaderColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}
