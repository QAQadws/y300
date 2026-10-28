import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  test('inline size memory is bounded and keeps recently read entries', () {
    final presentation = ForumHtmlBodyPresentation();
    addTearDown(presentation.dispose);
    for (var image = 0; image < 128; image++) {
      presentation.recordInlineImageSize(image, const Size(96, 64));
    }
    expect(presentation.inlineImageSizeFor(0), const Size(96, 64));
    presentation.recordInlineImageSize(128, const Size(48, 32));
    expect(presentation.inlineImageSizeFor(1), isNull);
    expect(presentation.inlineImageSizeFor(0), const Size(96, 64));
    expect(presentation.inlineImageSizeFor(128), const Size(48, 32));
  });

  test('invalid hints cannot replace a confirmed inline size', () {
    final presentation = ForumHtmlBodyPresentation();
    addTearDown(presentation.dispose);
    presentation.recordInlineImageSize('image', const Size(96, 64));
    for (final size in [
      Size.zero,
      const Size(-1, 32),
      const Size(32, double.infinity),
      const Size(double.nan, 32),
    ]) {
      presentation.recordInlineImageSize('image', size);
    }
    expect(presentation.inlineImageSizeFor('image'), const Size(96, 64));
  });

  test('disposed owners ignore late hints and release remembered geometry', () {
    final presentation = ForumHtmlBodyPresentation();
    presentation.recordInlineImageSize('image', const Size(96, 64));
    presentation.dispose();
    expect(presentation.inlineImageSizeFor('image'), isNull);
    presentation.recordInlineImageSize('late', const Size(48, 32));
    expect(presentation.inlineImageSizeFor('late'), isNull);
  });
}
