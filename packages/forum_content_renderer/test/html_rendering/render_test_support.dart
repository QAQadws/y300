import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'forum_html_test_theme.dart';

export 'forum_html_test_theme.dart';

const renderTestOptions = ForumHtmlRenderOptions(
  fontScale: 1.15,
  lineHeightScale: 1.5,
  paragraphSpacing: 12,
  preserveAuthorFontSize: true,
);

const renderTestLabels = ForumHtmlCollapseLabels(
  fallbackTitle: 'Content',
  expandedSemanticsLabel: 'Collapse content',
  collapsedSemanticsLabel: 'Expand content',
);

ForumHtmlPreparedRenderDocument prepareRenderTestDocument(
  String html, {
  String sourceId = 'render-test',
  ForumHtmlRenderOptions options = renderTestOptions,
}) =>
    const ForumHtmlPreparationPipeline(
      imagePolicy: _RenderTestImagePolicy(),
      resolveUrl: _resolveRenderTestUrl,
    ).prepare(
      html: html,
      options: options,
      theme: forumHtmlTestTheme,
      sourceId: sourceId,
      threadId: '100',
      imageCacheOwnerId: '100',
    );

String? _resolveRenderTestUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  return uri == null
      ? null
      : Uri.parse('https://bbs.yamibo.com/').resolveUri(uri).toString();
}

final class _RenderTestImagePolicy implements ForumHtmlPreparationImagePolicy {
  const _RenderTestImagePolicy();

  @override
  ForumHtmlPreparedImageResource prepareInline({
    required Uri url,
    required String? threadId,
    required String? imageCacheOwnerId,
    required int imageIndex,
    double? htmlWidth,
    double? htmlHeight,
    String? alt,
    String? title,
  }) => _RenderTestImageResource('test:$url');
}

final class _RenderTestImageResource implements ForumHtmlPreparedImageResource {
  const _RenderTestImageResource(this.cacheKey);

  @override
  final String cacheKey;
}
