import 'package:flutter/material.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_fragment_extractor.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_render_input.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_sample_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';

class ForumHtmlRendererPrototypePage extends StatefulWidget {
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
  State<ForumHtmlRendererPrototypePage> createState() =>
      _ForumHtmlRendererPrototypePageState();
}

class _ForumHtmlRendererPrototypePageState
    extends State<ForumHtmlRendererPrototypePage> {
  late ForumHtmlSampleDocument _selectedSample;
  Future<_ForumHtmlPrototypeLoadResult>? _loadFuture;

  @override
  void initState() {
    super.initState();
    _selectedSample = widget.samples.first;
    _loadFuture = _loadSelectedSample();
  }

  @override
  void didUpdateWidget(ForumHtmlRendererPrototypePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.samples != oldWidget.samples ||
        !widget.samples.contains(_selectedSample)) {
      _selectedSample = widget.samples.first;
      _loadFuture = _loadSelectedSample();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HTML 正文渲染原型')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SampleSelector(
              samples: widget.samples,
              selectedSample: _selectedSample,
              onSelected: _selectSample,
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
                    input: result.input!,
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
      _loadFuture = _loadSelectedSample();
    });
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

  Future<_ForumHtmlPrototypeLoadResult> _loadSelectedSample() async {
    final bundle = widget.assetBundle ?? DefaultAssetBundle.of(context);
    try {
      final rawHtml = await bundle.loadString(_selectedSample.assetPath);
      final input = widget.extractor.extract(
        sourceId: _selectedSample.id,
        rawHtml: rawHtml,
      );
      return _ForumHtmlPrototypeLoadResult.loaded(input);
    } on FlutterError catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('unable to load asset')) {
        return const _ForumHtmlPrototypeLoadResult.missingLocalAsset();
      }
      rethrow;
    }
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
    required this.input,
    required this.onTapUrl,
  });

  final ForumHtmlSampleDocument sample;
  final ForumHtmlRenderInput input;
  final Future<bool> Function(String url) onTapUrl;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('forum-html-prototype-loaded-view'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _DebugSummary(sample: sample, input: input),
        const SizedBox(height: 12),
        ForumHtmlWidgetPostRenderer(
          html: input.fragmentHtml,
          sourceId: input.sourceId,
          callbacks: ForumHtmlRenderCallbacks(onTapUrl: onTapUrl),
        ),
      ],
    );
  }
}

class _DebugSummary extends StatelessWidget {
  const _DebugSummary({required this.sample, required this.input});

  final ForumHtmlSampleDocument sample;
  final ForumHtmlRenderInput input;

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
              ],
            ),
          ),
        ),
      ),
    );
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
    required this.isMissingLocalAsset,
  });

  const _ForumHtmlPrototypeLoadResult.loaded(ForumHtmlRenderInput input)
    : this._(input: input, isMissingLocalAsset: false);

  const _ForumHtmlPrototypeLoadResult.missingLocalAsset()
    : this._(input: null, isMissingLocalAsset: true);

  final ForumHtmlRenderInput? input;
  final bool isMissingLocalAsset;
}
