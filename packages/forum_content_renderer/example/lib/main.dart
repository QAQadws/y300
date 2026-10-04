import 'package:flutter/material.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() => runApp(const ForumContentRendererExample());

class ForumContentRendererExample extends StatelessWidget {
  const ForumContentRendererExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Forum content renderer',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('Forum content renderer')),
      body: const SingleChildScrollView(
        child: Padding(padding: EdgeInsets.all(16), child: _ExampleBody()),
      ),
    ),
  );
}

class _ExampleBody extends StatelessWidget {
  const _ExampleBody();

  static const _html =
      '<p>A renderer with explicit Host inputs.</p>'
      '<div class="showcollapse_box" id="details">'
      '<div class="showcollapse_title">Details</div>'
      '<div class="showcollapse_content">'
      '<p>This body uses the public renderer without an application provider.</p>'
      '</div></div>';

  static const _options = ForumHtmlRenderOptions(
    fontScale: 1,
    lineHeightScale: 1.5,
    paragraphSpacing: 12,
    preserveAuthorFontSize: true,
  );

  static const _labels = ForumHtmlCollapseLabels(
    fallbackTitle: 'Content',
    expandedSemanticsLabel: 'Collapse content',
    collapsedSemanticsLabel: 'Expand content',
  );

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final theme = const ForumHtmlRenderThemeFactory().fromMaterialTheme(
      theme: materialTheme,
      surface: materialTheme.colorScheme.surface,
    );
    final document =
        const ForumHtmlPreparationPipeline(
          imagePolicy: _TextOnlyImagePolicy(),
          resolveUrl: _resolveExampleUrl,
        ).prepare(
          html: _html,
          options: _options,
          theme: theme,
          sourceId: 'example',
          threadId: null,
          imageCacheOwnerId: null,
        );
    return ForumHtmlRenderer(
      preparedDocument: document,
      theme: theme,
      options: _options,
      labels: _labels,
      sourceId: 'example',
      buildAsync: false,
    );
  }
}

String? _resolveExampleUrl(String rawUrl) => Uri.tryParse(rawUrl)?.toString();

// This text-only example does not provide an image loading Host.
final class _TextOnlyImagePolicy implements ForumHtmlPreparationImagePolicy {
  const _TextOnlyImagePolicy();

  @override
  ForumHtmlPreparedImageResource? prepareInline({
    required Uri url,
    required String? threadId,
    required String? imageCacheOwnerId,
    required int imageIndex,
    double? htmlWidth,
    double? htmlHeight,
    String? alt,
    String? title,
  }) => null;
}
