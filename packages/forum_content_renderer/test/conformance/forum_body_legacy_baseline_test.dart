import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_html_comparison/forum_html_comparison.dart';

import '../html_rendering/render_test_support.dart';
import 'forum_body_corpus.dart';

void main() {
  for (final sample in forumBodyCases) {
    testWidgets('legacy baseline preserves ${sample.id}', (tester) async {
      final document = prepareRenderTestDocument(
        sample.html,
        sourceId: sample.id,
        options: renderTestOptions.copyWith(preserveAuthorFontFamily: false),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 344,
                child: SingleChildScrollView(
                  child: ForumHtmlRenderer(
                    preparedDocument: document,
                    theme: forumHtmlTestTheme,
                    options: renderTestOptions.copyWith(
                      preserveAuthorFontFamily: false,
                    ),
                    labels: renderTestLabels,
                    sourceId: sample.id,
                    imageHost: const _OfflineImageHost(),
                    buildAsync: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((widget) => widget.text.toPlainText())
          .join('\n');
      for (final token in sample.visibleTokens) {
        expect(text, contains(token), reason: sample.id);
      }
      expect(tester.takeException(), isNull, reason: sample.id);
    });
  }
}

// Synthetic resources never perform I/O, so geometry stays reproducible.
final class _OfflineImageHost implements ForumHtmlImageHost {
  const _OfflineImageHost();

  @override
  ForumHtmlDisplayImage resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => _OfflineImage(url.toString(), isSticker, htmlSize);

  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) async =>
      (size: image.htmlSize ?? const Size(80, 40), layout: image.initialLayout);

  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) {}

  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) async {}

  @override
  Widget buildImage({
    required ForumHtmlDisplayImage image,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    VoidCallback? onRetry,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) => SizedBox(
    width: width,
    height: height,
    child: const ColoredBox(color: Colors.grey),
  );
}

final class _OfflineImage implements ForumHtmlDisplayImage {
  const _OfflineImage(this.sourceUrl, this.isSticker, this.htmlSize);
  @override
  final String sourceUrl;
  @override
  final bool isSticker;
  @override
  final Size? htmlSize;
  @override
  String get cacheKey => sourceUrl;
  @override
  Object get identity => (sourceUrl, isSticker, htmlSize);
  @override
  ForumHtmlImageLayout get initialLayout => ForumHtmlImageLayout(
    aspectRatio: htmlSize?.aspectRatio,
    displaySize: htmlSize,
  );
}
