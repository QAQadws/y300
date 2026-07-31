import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/services/thread_detail_html_parser.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_fragment_extractor.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_render_input.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_sample_document.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_settings_sheet.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_theme_factory.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_adaptation_result.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

class ForumHtmlRendererPrototypePage extends ConsumerStatefulWidget {
  const ForumHtmlRendererPrototypePage({
    super.key,
    this.assetBundle,
    this.extractor = const DefaultForumHtmlFragmentExtractor(),
    this.samples = forumHtmlPrototypeSamples,
  });

  final AssetBundle? assetBundle;
  final ForumHtmlFragmentExtractor extractor;
  final List<ForumHtmlSampleDocument> samples;

  @override
  ConsumerState<ForumHtmlRendererPrototypePage> createState() =>
      _ForumHtmlRendererPrototypePageState();
}

class _ForumHtmlRendererPrototypePageState
    extends ConsumerState<ForumHtmlRendererPrototypePage> {
  late ForumHtmlSampleDocument _selectedSample;
  ForumHtmlBrightness _previewBrightness = ForumHtmlBrightness.light;
  TextConversionMode _prototypeConversionMode = TextConversionMode.none;
  ForumHtmlReaderPreferences? _loadPreferences;
  Future<_ForumHtmlPrototypeLoadResult>? _loadFuture;

  @override
  void initState() {
    super.initState();
    _selectedSample = widget.samples.first;
  }

  @override
  void didUpdateWidget(ForumHtmlRendererPrototypePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.samples != oldWidget.samples ||
        !widget.samples.contains(_selectedSample)) {
      _selectedSample = widget.samples.first;
      _loadPreferences = null;
      _loadFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preferencesAsync = ref.watch(
      forumHtmlReaderPreferencesControllerProvider,
    );
    final preferences =
        preferencesAsync.value ?? ForumHtmlReaderPreferences.defaults();
    if (_loadPreferences == null) {
      _loadPreferences = preferences;
      _loadFuture ??= _loadSelectedSample(
        preferences,
        conversionMode: _prototypeConversionMode,
      );
    } else if (_loadPreferences != preferences) {
      _loadPreferences = preferences;
      _loadFuture = _loadSelectedSample(
        preferences,
        conversionMode: _prototypeConversionMode,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.threadPrototypeTitle),
        actions: [
          IconButton(
            key: const Key('forum-html-prototype-reader-settings-button'),
            tooltip: l10n.threadHtmlConversionSettings,
            icon: const Icon(Icons.tune),
            onPressed: _openReaderSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SampleSelector(
              samples: widget.samples,
              selectedSample: _selectedSample,
              onSelected: _selectSample,
            ),
            _ConversionSelector(
              mode: _prototypeConversionMode,
              onSelected: _selectConversionMode,
            ),
            _ThemePreviewSelector(
              brightness: _previewBrightness,
              onSelected: _selectPreviewBrightness,
            ),
            Expanded(
              child: FutureBuilder<_ForumHtmlPrototypeLoadResult>(
                future: _loadFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        key: Key('forum-html-prototype-loading'),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(
                      sample: _selectedSample,
                      message: l10n.threadPrototypeLoadFailed(
                        LocalizedErrorSummary.resolve(l10n, snapshot.error),
                      ),
                    );
                  }

                  final result = snapshot.data;
                  if (result == null) {
                    return _ErrorState(
                      sample: _selectedSample,
                      message: l10n.threadPrototypeEmptyResult,
                    );
                  }
                  if (result.isMissingLocalAsset) {
                    return _ErrorState(
                      sample: _selectedSample,
                      message: l10n.threadPrototypeMissingAsset(
                        _selectedSample.sourceDocPath,
                        _selectedSample.assetPath,
                      ),
                    );
                  }
                  final previewTheme = _previewThemeData(_previewBrightness);
                  return Theme(
                    data: previewTheme,
                    child: ColoredBox(
                      color: previewTheme.scaffoldBackgroundColor,
                      child: _LoadedSampleView(
                        sample: _selectedSample,
                        result: result,
                        onTapUrl: _handleTapUrl,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectSample(ForumHtmlSampleDocument sample) {
    if (sample.id == _selectedSample.id) {
      return;
    }
    setState(() {
      _selectedSample = sample;
      _loadFuture = _loadSelectedSample(
        _loadPreferences ?? ForumHtmlReaderPreferences.defaults(),
        conversionMode: _prototypeConversionMode,
      );
    });
  }

  void _selectConversionMode(TextConversionMode mode) {
    if (mode == _prototypeConversionMode) {
      return;
    }
    final preferences =
        _loadPreferences ?? ForumHtmlReaderPreferences.defaults();
    setState(() {
      _prototypeConversionMode = mode;
      _loadFuture = _loadSelectedSample(preferences, conversionMode: mode);
    });
  }

  void _selectPreviewBrightness(ForumHtmlBrightness brightness) {
    if (brightness == _previewBrightness) {
      return;
    }
    setState(() => _previewBrightness = brightness);
  }

  void _openReaderSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => const ForumHtmlReaderSettingsSheet(),
    );
  }

  Future<bool> _handleTapUrl(String url) async {
    if (!mounted) {
      return false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('forum-html-prototype-link-snackbar'),
        content: Text(AppLocalizations.of(context).threadPrototypeLink(url)),
      ),
    );
    return true;
  }

  Future<_ForumHtmlPrototypeLoadResult> _loadSelectedSample(
    ForumHtmlReaderPreferences preferences, {
    required TextConversionMode conversionMode,
  }) async {
    final bundle = widget.assetBundle ?? DefaultAssetBundle.of(context);
    try {
      final rawHtml = await bundle.loadString(_selectedSample.assetPath);
      if (_selectedSample.renderMode ==
          ForumHtmlSampleRenderMode.threadDetail) {
        return _loadThreadDetailSample(
          rawHtml: rawHtml,
          preferences: preferences,
          conversionMode: conversionMode,
        );
      }
      final input = widget.extractor.extract(
        sourceId: _selectedSample.id,
        rawHtml: rawHtml,
      );
      final converter = ref.read(textConverterProvider(conversionMode));
      final conversionResult = await ref
          .read(htmlTextNodeConversionServiceProvider)
          .convert(html: input.fragmentHtml, converter: converter);
      return _ForumHtmlPrototypeLoadResult.loaded(
        input: input,
        preferences: preferences,
        conversionMode: conversionMode,
        conversionResult: conversionResult,
      );
    } on FlutterError catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('unable to load asset')) {
        return const _ForumHtmlPrototypeLoadResult.missingLocalAsset();
      }
      rethrow;
    }
  }

  Future<_ForumHtmlPrototypeLoadResult> _loadThreadDetailSample({
    required String rawHtml,
    required ForumHtmlReaderPreferences preferences,
    required TextConversionMode conversionMode,
  }) async {
    final parsed = const ThreadDetailHtmlParser().parse(
      rawHtml,
      fallbackTid: _selectedSample.id,
      fallbackPage: 1,
      fallbackSubject: _selectedSample.title,
    );
    final converter = ref.read(textConverterProvider(conversionMode));
    final conversionService = ref.read(htmlTextNodeConversionServiceProvider);
    var convertedTextNodeCount = 0;
    final convertedPosts = <ThreadPost>[];
    for (final post in parsed.posts) {
      final converted = await conversionService.convert(
        html: post.message,
        converter: converter,
      );
      convertedTextNodeCount += converted.convertedTextNodeCount;
      convertedPosts.add(_copyPostWithMessage(post, converted.html));
    }

    return _ForumHtmlPrototypeLoadResult.loadedThreadDetail(
      threadData: _copyThreadDataWithPosts(parsed, convertedPosts),
      preferences: preferences,
      conversionMode: conversionMode,
      conversionResult: HtmlTextNodeConversionResult(
        html: '',
        convertedTextNodeCount: convertedTextNodeCount,
        converterId: converter.id,
      ),
    );
  }

  ThreadPost _copyPostWithMessage(ThreadPost post, String message) {
    return ThreadPost(
      pid: post.pid,
      author: post.author,
      authorId: post.authorId,
      message: message,
      number: post.number,
      isFirst: post.isFirst,
      dateline: post.dateline,
      avatarUrl: post.avatarUrl,
      replyUrl: post.replyUrl,
      rateUrl: post.rateUrl,
      commentUrl: post.commentUrl,
      rateSummary: post.rateSummary,
      ratingSummary: post.ratingSummary,
      poll: post.poll,
      tagLinks: post.tagLinks,
      comments: post.comments,
      attachmentImages: post.attachmentImages,
    );
  }

  ThreadDetailData _copyThreadDataWithPosts(
    ThreadDetailData data,
    List<ThreadPost> posts,
  ) {
    return ThreadDetailData(
      tid: data.tid,
      fid: data.fid,
      typeid: data.typeid,
      typeName: data.typeName,
      forumName: data.forumName,
      forumUrl: data.forumUrl,
      subject: data.subject,
      author: data.author,
      replies: data.replies,
      views: data.views,
      currentPage: data.currentPage,
      perPage: data.perPage,
      posts: List<ThreadPost>.unmodifiable(posts),
      lastPage: data.lastPage,
      previousPageUrl: data.previousPageUrl,
      nextPageUrl: data.nextPageUrl,
      reverseOrderUrl: data.reverseOrderUrl,
      onlyAuthorUrl: data.onlyAuthorUrl,
      favoriteUrl: data.favoriteUrl,
      shareUrl: data.shareUrl,
      homeUrl: data.homeUrl,
      desktopUrl: data.desktopUrl,
    );
  }
}

class _ConversionSelector extends StatelessWidget {
  const _ConversionSelector({required this.mode, required this.onSelected});

  final TextConversionMode mode;
  final ValueChanged<TextConversionMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SegmentedButton<TextConversionMode>(
        key: const Key('forum-html-prototype-conversion-selector'),
        segments: [
          ButtonSegment(
            value: TextConversionMode.none,
            label: Text(
              l10n.threadHtmlConversionOriginal,
              key: const Key('forum-html-prototype-conversion-none'),
            ),
          ),
          ButtonSegment(
            value: TextConversionMode.toSimplified,
            label: Text(
              l10n.threadHtmlConversionSimplified,
              key: const Key('forum-html-prototype-conversion-simplified'),
            ),
          ),
          ButtonSegment(
            value: TextConversionMode.toTraditional,
            label: Text(
              l10n.threadHtmlConversionTraditional,
              key: const Key('forum-html-prototype-conversion-traditional'),
            ),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (selection) => onSelected(selection.single),
      ),
    );
  }
}

class _ThemePreviewSelector extends StatelessWidget {
  const _ThemePreviewSelector({
    required this.brightness,
    required this.onSelected,
  });

  final ForumHtmlBrightness brightness;
  final ValueChanged<ForumHtmlBrightness> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<ForumHtmlBrightness>(
          key: const Key('forum-html-prototype-theme-preview-selector'),
          segments: [
            ButtonSegment(
              value: ForumHtmlBrightness.light,
              icon: const Icon(Icons.light_mode_outlined),
              label: Text(l10n.threadPrototypeThemeLight),
            ),
            ButtonSegment(
              value: ForumHtmlBrightness.dark,
              icon: const Icon(Icons.dark_mode_outlined),
              label: Text(l10n.threadPrototypeThemeDark),
            ),
          ],
          selected: {brightness},
          onSelectionChanged: (selection) => onSelected(selection.single),
        ),
      ),
    );
  }
}

class _SampleSelector extends StatelessWidget {
  const _SampleSelector({
    required this.samples,
    required this.selectedSample,
    required this.onSelected,
  });

  final List<ForumHtmlSampleDocument> samples;
  final ForumHtmlSampleDocument selectedSample;
  final ValueChanged<ForumHtmlSampleDocument> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('forum-html-prototype-sample-selector'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          for (final sample in samples) ...[
            ChoiceChip(
              key: Key('forum-html-prototype-sample-${sample.id}'),
              label: Text(sample.title),
              selected: sample.id == selectedSample.id,
              onSelected: (_) => onSelected(sample),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _LoadedSampleView extends StatelessWidget {
  const _LoadedSampleView({
    required this.sample,
    required this.result,
    required this.onTapUrl,
  });

  final ForumHtmlSampleDocument sample;
  final _ForumHtmlPrototypeLoadResult result;
  final Future<bool> Function(String url) onTapUrl;

  @override
  Widget build(BuildContext context) {
    final threadData = result.threadData;
    if (threadData != null) {
      return _LoadedThreadDetailSampleView(
        sample: sample,
        result: result,
        threadData: threadData,
        onTapUrl: onTapUrl,
      );
    }
    final input = result.input!;
    final conversionResult = result.conversionResult!;
    final preferences = result.preferences!;
    final materialTheme = Theme.of(context);
    final renderTheme = const ForumHtmlRenderThemeFactory().fromMaterialTheme(
      theme: materialTheme,
      surface: materialTheme.scaffoldBackgroundColor,
    );
    final prepared = const DefaultForumHtmlRenderPreparer().prepare(
      html: conversionResult.html,
      preferences: preferences,
      theme: renderTheme,
      sourceId: input.sourceId,
      threadId: null,
      imageCacheOwnerId: null,
    );
    return ListView(
      key: const Key('forum-html-prototype-loaded-view'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _DebugSummary(
          sample: sample,
          input: input,
          preferences: preferences,
          conversionMode: result.conversionMode!,
          conversionResult: conversionResult,
          theme: renderTheme,
          adaptationStats: prepared.themeAdaptationStats,
        ),
        const SizedBox(height: 12),
        ForumHtmlWidgetPostRenderer(
          html: conversionResult.html,
          theme: renderTheme,
          sourceId: input.sourceId,
          preferences: preferences,
          preparedDocument: prepared,
          callbacks: ForumHtmlRenderCallbacks(onTapUrl: onTapUrl),
        ),
      ],
    );
  }
}

class _LoadedThreadDetailSampleView extends StatefulWidget {
  const _LoadedThreadDetailSampleView({
    required this.sample,
    required this.result,
    required this.threadData,
    required this.onTapUrl,
  });

  final ForumHtmlSampleDocument sample;
  final _ForumHtmlPrototypeLoadResult result;
  final ThreadDetailData threadData;
  final Future<bool> Function(String url) onTapUrl;

  @override
  State<_LoadedThreadDetailSampleView> createState() =>
      _LoadedThreadDetailSampleViewState();
}

class _LoadedThreadDetailSampleViewState
    extends State<_LoadedThreadDetailSampleView> {
  static const int _maxJitterLogEntries = 2000;

  late final ScrollController _scrollController;
  final List<String> _jitterLog = <String>[];
  bool _jitterRecording = false;
  DateTime? _jitterRecordingStartedAt;
  DateTime? _lastScrollLogAt;
  double? _lastScrollLogPixels;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_recordScrollSample);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_recordScrollSample);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threadState = _threadStateFromData(widget.threadData);
    final showJitterDiagnostics = widget.sample.id == 'jitter_test';
    return Column(
      key: const Key('forum-html-prototype-thread-loaded-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: _ThreadDebugSummary(
            sample: widget.sample,
            threadData: widget.threadData,
            preferences: widget.result.preferences!,
            conversionMode: widget.result.conversionMode!,
            conversionResult: widget.result.conversionResult!,
          ),
        ),
        if (showJitterDiagnostics)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _JitterDiagnosticsControls(
              recording: _jitterRecording,
              logCount: _jitterLog.length,
              onRecordingChanged: _setJitterRecording,
              onCopy: _copyJitterLog,
              onClear: _clearJitterLog,
            ),
          ),
        Expanded(
          child: ThreadDetailContent(
            state: threadState,
            scrollController: _scrollController,
            imageHeaderBuilder: null,
            imageReferer: widget.threadData.desktopUrl ?? '',
            onLoadPreviousPage: _showUnsupportedAction,
            onLoadNextPage: _showUnsupportedAction,
            onLoadPageNumber: (_) => _showUnsupportedAction(),
            onOpenAuthorProfile: (_) => _showUnsupportedAction(),
            onOpenCommentAuthorProfile: (_) => _showUnsupportedAction(),
            onCopyActionUrl: (_, url) => widget.onTapUrl(url),
            onOpenPostLink: (url) => widget.onTapUrl(url),
            onOpenPostImages: _handleOpenPostImages,
            onOpenPostActions: (_, _) => _showUnsupportedAction(),
            onPostBuilt: _recordPostBuilt,
            onScrollStabilizerEvent: _recordScrollStabilizerEvent,
            onTogglePollOption: (_, _) {},
            onSubmitPollVote: (_) => _showUnsupportedAction(),
          ),
        ),
      ],
    );
  }

  ThreadDetailPageState _threadStateFromData(ThreadDetailData data) {
    return ThreadDetailPageState(
      tid: data.tid,
      fid: data.fid,
      typeid: data.typeid,
      typeName: data.typeName,
      forumName: data.forumName,
      forumUrl: data.forumUrl,
      sourceTagName: null,
      contentKind: ThreadContentKind.forum,
      subject: data.subject,
      views: data.views,
      replies: data.replies,
      currentPage: data.currentPage,
      lastPage: data.lastPage,
      previousPageUrl: data.previousPageUrl,
      nextPageUrl: data.nextPageUrl,
      reverseOrderUrl: data.reverseOrderUrl,
      onlyAuthorUrl: data.onlyAuthorUrl,
      favoriteUrl: data.favoriteUrl,
      shareUrl: data.shareUrl,
      homeUrl: data.homeUrl,
      desktopUrl: data.desktopUrl,
      hasMore: data.hasMore,
      queryParameters: const <String, String>{},
      isLoadingInitial: false,
      isLoadingMore: false,
      posts: data.posts,
      isThreadFavorited: false,
      isThreadFavoriteActionLoading: false,
      threadFavoriteHint: null,
      selectedPollOptionIds: const <String>{},
      isPollVoteSubmitting: false,
      pollVoteHint: null,
      replyText: '',
      isReplySubmitting: false,
      replyHint: null,
    );
  }

  void _setJitterRecording(bool value) {
    if (value == _jitterRecording) {
      return;
    }
    if (value) {
      setState(() {
        _jitterLog.clear();
        _jitterRecordingStartedAt = DateTime.now();
        _lastScrollLogAt = null;
        _lastScrollLogPixels = null;
        _jitterRecording = true;
        _appendJitterLog(
          'session-start sample=${widget.sample.id} '
          'tid=${widget.threadData.tid} page=${widget.threadData.currentPage} '
          'posts=${widget.threadData.posts.length}',
        );
        _recordScrollSample(force: true);
      });
      return;
    }
    setState(() {
      _appendJitterLog('session-stop entries=${_jitterLog.length + 1}');
      _jitterRecording = false;
    });
  }

  Future<void> _copyJitterLog() async {
    final text = _jitterLog.isEmpty
        ? 'No jitter diagnostics were recorded.'
        : _jitterLog.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('forum-html-prototype-jitter-log-copied-snackbar'),
        content: Text(
          AppLocalizations.of(
            context,
          ).threadPrototypeJitterCopied(_jitterLog.length),
        ),
      ),
    );
  }

  void _clearJitterLog() {
    setState(() {
      _jitterLog.clear();
      _jitterRecordingStartedAt = _jitterRecording ? DateTime.now() : null;
      _lastScrollLogAt = null;
      _lastScrollLogPixels = null;
      if (_jitterRecording) {
        _appendJitterLog('session-reset');
        _recordScrollSample(force: true);
      }
    });
  }

  void _recordPostBuilt(int index) {
    _appendJitterLog('post-built index=$index');
  }

  void _recordScrollSample({bool force = false}) {
    if (!_jitterRecording) {
      return;
    }
    if (!_scrollController.hasClients) {
      _appendJitterLog('scroll unavailable=no-clients');
      return;
    }
    final now = DateTime.now();
    final position = _scrollController.position;
    final previousPixels = _lastScrollLogPixels;
    final delta = previousPixels == null
        ? 0.0
        : position.pixels - previousPixels;
    if (!force &&
        _lastScrollLogAt != null &&
        now.difference(_lastScrollLogAt!).inMilliseconds < 80 &&
        delta.abs() < 12) {
      return;
    }
    _lastScrollLogAt = now;
    _lastScrollLogPixels = position.pixels;
    _appendJitterLog(
      'scroll pixels=${_fmt(position.pixels)} delta=${_fmt(delta)} '
      'min=${_fmt(position.minScrollExtent)} '
      'max=${_fmt(position.maxScrollExtent)} '
      'viewport=${_fmt(position.viewportDimension)} '
      'dir=${position.userScrollDirection.name} '
      'scrolling=${position.isScrollingNotifier.value}',
    );
  }

  void _recordScrollStabilizerEvent(ThreadDetailScrollStabilizerEvent event) {
    _appendJitterLog(
      'stabilizer type=${event.type.name} reason=${event.reason} '
      'pixels=${_fmtNullable(event.scrollPixels)} '
      'target=${_fmtNullable(event.targetPixels)} '
      'pending=${_fmtNullable(event.pendingDelta)} '
      'deltaH=${_fmt(event.deltaHeight)} '
      'oldAR=${_fmt(event.oldAspectRatio)} newAR=${_fmt(event.newAspectRatio)} '
      'viewportTop=${_fmtNullable(event.viewportTop)} '
      'imageBottom=${_fmtNullable(event.imageBottom)} '
      'dir=${event.userScrollDirection ?? 'unknown'} '
      'scrolling=${event.isScrolling ?? false} '
      'key=${event.cacheKey} url=${_shortUrl(event.sourceUrl)}',
    );
  }

  void _appendJitterLog(String message) {
    if (!_jitterRecording) {
      return;
    }
    final start = _jitterRecordingStartedAt;
    final elapsed = start == null
        ? 0
        : DateTime.now().difference(start).inMilliseconds;
    _jitterLog.add('${elapsed.toString().padLeft(6)}ms $message');
    if (_jitterLog.length > _maxJitterLogEntries) {
      _jitterLog.removeRange(0, _jitterLog.length - _maxJitterLogEntries);
    }
  }

  String _fmt(double value) => value.toStringAsFixed(1);

  String _fmtNullable(double? value) => value == null ? 'null' : _fmt(value);

  String _shortUrl(String url) {
    final value = url.trim();
    if (value.length <= 96) {
      return value;
    }
    return '${value.substring(0, 48)}...${value.substring(value.length - 32)}';
  }

  void _handleOpenPostImages(
    ThreadPost post,
    ThreadPostImageOpenRequest request,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('forum-html-prototype-image-reader-snackbar'),
        content: Text(
          AppLocalizations.of(
            context,
          ).threadPrototypeImageOpened(post.number, request.initialIndex + 1),
        ),
      ),
    );
  }

  void _showUnsupportedAction() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('forum-html-prototype-thread-action-snackbar'),
        content: Text(
          AppLocalizations.of(context).threadPrototypeActionUnsupported,
        ),
      ),
    );
  }
}

class _JitterDiagnosticsControls extends StatelessWidget {
  const _JitterDiagnosticsControls({
    required this.recording,
    required this.logCount,
    required this.onRecordingChanged,
    required this.onCopy,
    required this.onClear,
  });

  final bool recording;
  final int logCount;
  final ValueChanged<bool> onRecordingChanged;
  final VoidCallback onCopy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      key: const Key('forum-html-prototype-jitter-log-panel'),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.threadPrototypeJitterTitle,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        recording
                            ? l10n.threadPrototypeJitterRecording
                            : l10n.threadPrototypeJitterCount(logCount),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  key: const Key('forum-html-prototype-jitter-log-switch'),
                  value: recording,
                  onChanged: onRecordingChanged,
                ),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  key: const Key('forum-html-prototype-jitter-log-copy'),
                  onPressed: recording || logCount == 0 ? null : onCopy,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(l10n.threadPrototypeCopyLog),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: const Key('forum-html-prototype-jitter-log-clear'),
                  onPressed: logCount == 0 ? null : onClear,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.commonClear),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadDebugSummary extends StatelessWidget {
  const _ThreadDebugSummary({
    required this.sample,
    required this.threadData,
    required this.preferences,
    required this.conversionMode,
    required this.conversionResult,
  });

  final ForumHtmlSampleDocument sample;
  final ThreadDetailData threadData;
  final ForumHtmlReaderPreferences preferences;
  final TextConversionMode conversionMode;
  final HtmlTextNodeConversionResult conversionResult;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.threadPrototypeThreadSummarySemantics,
      child: DecoratedBox(
        key: const Key('forum-html-prototype-thread-debug-summary'),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle.merge(
            style: textTheme.bodySmall,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.threadPrototypeSample(sample.title)),
                Text(l10n.threadPrototypeThread(threadData.subject)),
                Text(
                  l10n.threadPrototypePage(
                    threadData.currentPage,
                    threadData.lastPage?.toString() ?? '?',
                  ),
                ),
                Text(l10n.threadPrototypePosts(threadData.posts.length)),
                Text(
                  l10n.threadPrototypeConversionMode(
                    _prototypeConversionModeLabel(l10n, conversionMode),
                  ),
                ),
                Text(
                  l10n.threadPrototypeConverter(conversionResult.converterId),
                ),
                Text(
                  l10n.threadPrototypeConvertedNodes(
                    conversionResult.convertedTextNodeCount,
                  ),
                ),
                Text(
                  l10n.threadPrototypePreviewTheme(
                    _prototypeThemeLabel(
                      l10n,
                      Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                ),
                Text(
                  l10n.threadPrototypeTypography(
                    (preferences.typography.fontScale * 100).round(),
                    preferences.typography.lineHeightScale.toStringAsFixed(1),
                  ),
                ),
                Text(
                  l10n.threadPrototypeThemeAdaptation(
                    preferences.preserveAuthorFontSize
                        ? 'preserved'
                        : 'unified',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DebugSummary extends StatelessWidget {
  const _DebugSummary({
    required this.sample,
    required this.input,
    required this.preferences,
    required this.conversionMode,
    required this.conversionResult,
    required this.theme,
    required this.adaptationStats,
  });

  final ForumHtmlSampleDocument sample;
  final ForumHtmlRenderInput input;
  final ForumHtmlReaderPreferences preferences;
  final TextConversionMode conversionMode;
  final HtmlTextNodeConversionResult conversionResult;
  final ForumHtmlThemeContext theme;
  final ForumHtmlThemeAdaptationStats adaptationStats;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.threadPrototypeSummarySemantics,
      child: DecoratedBox(
        key: const Key('forum-html-prototype-debug-summary'),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle.merge(
            style: textTheme.bodySmall,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.threadPrototypeSample(sample.title)),
                Text(l10n.threadPrototypeRawHtmlLength(input.rawHtml.length)),
                Text(
                  l10n.threadPrototypeFragmentLength(input.fragmentHtml.length),
                ),
                Text(
                  l10n.threadPrototypeConversionMode(
                    _prototypeConversionModeLabel(l10n, conversionMode),
                  ),
                ),
                Text(
                  l10n.threadPrototypeConverter(conversionResult.converterId),
                ),
                Text(
                  l10n.threadPrototypeConvertedNodes(
                    conversionResult.convertedTextNodeCount,
                  ),
                ),
                Text(
                  l10n.threadPrototypePreviewTheme(
                    _prototypeThemeLabel(
                      l10n,
                      theme.brightness == ForumHtmlBrightness.dark,
                    ),
                  ),
                  key: const Key('forum-html-prototype-preview-theme'),
                ),
                Text(
                  l10n.threadPrototypeAdaptedColors(
                    adaptationStats.remappedForegroundCount,
                    adaptationStats.explicitForegroundCount,
                    adaptationStats.remappedBackgroundCount,
                    adaptationStats.explicitBackgroundCount,
                  ),
                  key: const Key('forum-html-prototype-adaptation-counts'),
                ),
                Text(
                  l10n.threadPrototypeAdaptationFallbacks(
                    adaptationStats.semanticFallbackCount,
                    adaptationStats.unsupportedColorCount,
                    adaptationStats.concealedTextRangeCount,
                  ),
                ),
                Text(
                  l10n.threadPrototypeMinimumContrast(
                    adaptationStats.minimumResultContrast?.toStringAsFixed(2) ??
                        '-',
                  ),
                  key: const Key('forum-html-prototype-minimum-contrast'),
                ),
                Text(
                  l10n.threadPrototypeTypography(
                    (preferences.typography.fontScale * 100).round(),
                    preferences.typography.lineHeightScale.toStringAsFixed(1),
                  ),
                ),
                Text(
                  l10n.threadPrototypeThemeAdaptation(
                    preferences.preserveAuthorFontSize
                        ? 'preserved'
                        : 'unified',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _prototypeConversionModeLabel(
  AppLocalizations l10n,
  TextConversionMode mode,
) {
  return switch (mode) {
    TextConversionMode.none => l10n.threadHtmlConversionOriginal,
    TextConversionMode.toSimplified => l10n.threadHtmlConversionSimplified,
    TextConversionMode.toTraditional => l10n.threadHtmlConversionTraditional,
  };
}

String _prototypeThemeLabel(AppLocalizations l10n, bool isDark) {
  return isDark
      ? l10n.threadPrototypeThemeDark
      : l10n.threadPrototypeThemeLight;
}

ThemeData _previewThemeData(ForumHtmlBrightness brightness) {
  return brightness == ForumHtmlBrightness.dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.sample, required this.message});

  final ForumHtmlSampleDocument sample;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('forum-html-prototype-error-state'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              sample.title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ForumHtmlPrototypeLoadResult {
  const _ForumHtmlPrototypeLoadResult._({
    required this.input,
    required this.threadData,
    required this.preferences,
    required this.conversionMode,
    required this.conversionResult,
    required this.isMissingLocalAsset,
  });

  const _ForumHtmlPrototypeLoadResult.loaded({
    required ForumHtmlRenderInput input,
    required ForumHtmlReaderPreferences preferences,
    required TextConversionMode conversionMode,
    required HtmlTextNodeConversionResult conversionResult,
  }) : this._(
         input: input,
         threadData: null,
         preferences: preferences,
         conversionMode: conversionMode,
         conversionResult: conversionResult,
         isMissingLocalAsset: false,
       );

  const _ForumHtmlPrototypeLoadResult.loadedThreadDetail({
    required ThreadDetailData threadData,
    required ForumHtmlReaderPreferences preferences,
    required TextConversionMode conversionMode,
    required HtmlTextNodeConversionResult conversionResult,
  }) : this._(
         input: null,
         threadData: threadData,
         preferences: preferences,
         conversionMode: conversionMode,
         conversionResult: conversionResult,
         isMissingLocalAsset: false,
       );

  const _ForumHtmlPrototypeLoadResult.missingLocalAsset()
    : this._(
        input: null,
        threadData: null,
        preferences: null,
        conversionMode: null,
        conversionResult: null,
        isMissingLocalAsset: true,
      );

  final ForumHtmlRenderInput? input;
  final ThreadDetailData? threadData;
  final ForumHtmlReaderPreferences? preferences;
  final TextConversionMode? conversionMode;
  final HtmlTextNodeConversionResult? conversionResult;
  final bool isMissingLocalAsset;
}
