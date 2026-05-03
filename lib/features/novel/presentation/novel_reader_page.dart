import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/widgets/reader_style_panel.dart';

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
  bool _stylePanelVisible = false;
  bool _hasRestoredOffset = false;

  NovelReaderArgs get _args =>
      NovelReaderArgs(novelId: widget.novelId, episodeId: widget.initialEpisodeId);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
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
      appBar: AppBar(
        title: const Text('小说阅读'),
        actions: [
          IconButton(
            key: const Key('novel-reader-style-button'),
            tooltip: '样式',
            icon: const Icon(Icons.tune),
            onPressed: () {
              setState(() {
                _stylePanelVisible = !_stylePanelVisible;
              });
            },
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载阅读器失败：$error')),
        data: (viewState) {
          _restoreOffsetIfNeeded(viewState.currentOffset);

          final colors = _resolveColors(viewState.preferences.themeMode);
          return Container(
            color: colors.background,
            child: Column(
              children: [
                _buildEpisodeSelector(viewState, controller),
                Expanded(
                  child: ListView.separated(
                    key: const Key('novel-reader-paragraph-list'),
                    controller: _scrollController,
                    padding: EdgeInsets.all(viewState.preferences.pagePadding),
                    itemCount: viewState.currentContent.paragraphs.length,
                    separatorBuilder: (context, index) => SizedBox(height: viewState.preferences.paragraphSpacing),
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
                  ),
                ),
                if (_stylePanelVisible)
                  ReaderStylePanel(
                    preferences: viewState.preferences,
                    onPreferencesChanged: controller.updatePreferences,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEpisodeSelector(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) {
    return Container(
      key: const Key('novel-reader-episode-selector'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButton<String>(
        value: viewState.currentEpisode.episodeId,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: viewState.episodes
            .map(
              (episode) => DropdownMenuItem<String>(
                value: episode.episodeId,
                child: Text(
                  episode.episodeTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (episodeId) {
          if (episodeId == null) {
            return;
          }
          _hasRestoredOffset = false;
          _scrollController.jumpTo(0);
          controller.openEpisode(episodeId);
        },
      ),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    ref
        .read(novelReaderControllerProvider(_args).notifier)
        .onScrollOffsetChanged(_scrollController.offset);
  }

  void _restoreOffsetIfNeeded(double offset) {
    if (_hasRestoredOffset || !_scrollController.hasClients || offset <= 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _hasRestoredOffset) {
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0, max));
      _hasRestoredOffset = true;
    });
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

class _ReaderColors {
  const _ReaderColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}
