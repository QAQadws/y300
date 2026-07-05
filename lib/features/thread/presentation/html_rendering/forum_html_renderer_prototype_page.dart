import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_fragment_extractor.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_render_input.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_sample_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_settings_sheet.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';

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
    final preferencesAsync = ref.watch(
      forumHtmlReaderPreferencesControllerProvider,
    );
    final preferences =
        preferencesAsync.value ?? ForumHtmlReaderPreferences.defaults();
    if (_loadPreferences == null) {
      _loadPreferences = preferences;
      _loadFuture ??= _loadSelectedSample(preferences);
    } else if (_loadPreferences != preferences) {
      _loadPreferences = preferences;
      _loadFuture = _loadSelectedSample(preferences);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('HTML 正文渲染原型'),
        actions: [
          IconButton(
            key: const Key('forum-html-prototype-reader-settings-button'),
            tooltip: '阅读设置',
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
              mode: preferences.conversionMode,
              onSelected: _selectConversionMode,
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
                      message: '样例加载失败：${snapshot.error}',
                    );
                  }

                  final result = snapshot.data;
                  if (result == null) {
                    return _ErrorState(
                      sample: _selectedSample,
                      message: '样例加载失败：结果为空',
                    );
                  }
                  if (result.isMissingLocalAsset) {
                    return _ErrorState(
                      sample: _selectedSample,
                      message:
                          '本地样例未找到，请从 ${_selectedSample.sourceDocPath} '
                          '复制到 ${_selectedSample.assetPath}',
                    );
                  }
                  return _LoadedSampleView(
                    sample: _selectedSample,
                    result: result,
                    onTapUrl: _handleTapUrl,
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
      );
    });
  }

  void _selectConversionMode(TextConversionMode mode) {
    final current =
        ref.read(forumHtmlReaderPreferencesControllerProvider).value ??
        ForumHtmlReaderPreferences.defaults();
    if (mode == current.conversionMode) {
      return;
    }
    ref
        .read(forumHtmlReaderPreferencesControllerProvider.notifier)
        .setConversionMode(mode);
  }

  void _openReaderSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
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
        content: Text('链接：$url'),
      ),
    );
    return true;
  }

  Future<_ForumHtmlPrototypeLoadResult> _loadSelectedSample(
    ForumHtmlReaderPreferences preferences,
  ) async {
    final bundle = widget.assetBundle ?? DefaultAssetBundle.of(context);
    final conversionMode = preferences.conversionMode;
    try {
      final rawHtml = await bundle.loadString(_selectedSample.assetPath);
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
}

class _ConversionSelector extends StatelessWidget {
  const _ConversionSelector({required this.mode, required this.onSelected});

  final TextConversionMode mode;
  final ValueChanged<TextConversionMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SegmentedButton<TextConversionMode>(
        key: const Key('forum-html-prototype-conversion-selector'),
        segments: const [
          ButtonSegment(
            value: TextConversionMode.none,
            label: Text('原文', key: Key('forum-html-prototype-conversion-none')),
          ),
          ButtonSegment(
            value: TextConversionMode.toSimplified,
            label: Text(
              '转简',
              key: Key('forum-html-prototype-conversion-simplified'),
            ),
          ),
          ButtonSegment(
            value: TextConversionMode.toTraditional,
            label: Text(
              '转繁',
              key: Key('forum-html-prototype-conversion-traditional'),
            ),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (selection) => onSelected(selection.single),
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
    final input = result.input!;
    final conversionResult = result.conversionResult!;
    final preferences = result.preferences!;
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
        ),
        const SizedBox(height: 12),
        ForumHtmlWidgetPostRenderer(
          html: conversionResult.html,
          sourceId: input.sourceId,
          preferences: preferences,
          callbacks: ForumHtmlRenderCallbacks(onTapUrl: onTapUrl),
        ),
      ],
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
  });

  final ForumHtmlSampleDocument sample;
  final ForumHtmlRenderInput input;
  final ForumHtmlReaderPreferences preferences;
  final TextConversionMode conversionMode;
  final HtmlTextNodeConversionResult conversionResult;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: 'HTML 原型样例摘要',
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
                Text('样例：${sample.title}'),
                Text('原 HTML：${input.rawHtml.length} 字符'),
                Text('正文 fragment：${input.fragmentHtml.length} 字符'),
                Text('转换模式：${_conversionModeLabel(conversionMode)}'),
                Text('转换器：${conversionResult.converterId}'),
                Text('转换文本节点：${conversionResult.convertedTextNodeCount} 个'),
                Text(preferences.typographyDebugLabel),
                Text(preferences.authorStyleDebugLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _conversionModeLabel(TextConversionMode mode) {
    return switch (mode) {
      TextConversionMode.none => '原文',
      TextConversionMode.toSimplified => '转简',
      TextConversionMode.toTraditional => '转繁',
    };
  }
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
         preferences: preferences,
         conversionMode: conversionMode,
         conversionResult: conversionResult,
         isMissingLocalAsset: false,
       );

  const _ForumHtmlPrototypeLoadResult.missingLocalAsset()
    : this._(
        input: null,
        preferences: null,
        conversionMode: null,
        conversionResult: null,
        isMissingLocalAsset: true,
      );

  final ForumHtmlRenderInput? input;
  final ForumHtmlReaderPreferences? preferences;
  final TextConversionMode? conversionMode;
  final HtmlTextNodeConversionResult? conversionResult;
  final bool isMissingLocalAsset;
}
