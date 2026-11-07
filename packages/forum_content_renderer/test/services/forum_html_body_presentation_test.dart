import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  test(
    'confirmed image layout memory is bounded and ignores invalid or retired writes',
    () {
      final presentation = ForumHtmlBodyPresentation();
      const layout = ForumHtmlImageLayout(aspectRatio: 2);
      for (var i = 0; i < 128; i++) {
        presentation.recordImageLayout(i, layout);
      }
      expect(presentation.imageLayoutFor(0), layout);
      presentation.recordImageLayout(128, layout);
      expect(presentation.imageLayoutFor(1), isNull);
      expect(presentation.imageLayoutFor(0), layout);
      for (final invalid in [
        const ForumHtmlImageLayout(isFallback: true, aspectRatio: 1),
        const ForumHtmlImageLayout(aspectRatio: double.nan),
        const ForumHtmlImageLayout(aspectRatio: 0),
        const ForumHtmlImageLayout(displaySize: Size(-1, 2), aspectRatio: 2),
      ]) {
        presentation.recordImageLayout(0, invalid);
      }
      expect(presentation.imageLayoutFor(0), layout);
      presentation.dispose();
      expect(presentation.imageLayoutFor(0), isNull);
      presentation.recordImageLayout('late', layout);
      expect(presentation.imageLayoutFor('late'), isNull);
    },
  );

  testWidgets('retained height follows the current published layout', (
    tester,
  ) async {
    final presentation = ForumHtmlBodyPresentation();
    addTearDown(presentation.dispose);
    final phase = ValueNotifier(ForumHtmlBodyLayoutPhase.built);
    addTearDown(phase.dispose);
    const body = Key('body');

    Future<void> pumpBody(double height, {int revision = 1}) =>
        tester.pumpWidget(
          Center(
            child: ForumHtmlBodyLayout.observed(
              key: body,
              presentation: presentation,
              sourceId: 'floor',
              revision: revision,
              phase: () => phase.value,
              child: SizedBox(height: height),
            ),
          ),
        );

    Future<void> expectHeight(double childHeight, double bodyHeight) async {
      await pumpBody(childHeight);
      expect(tester.getSize(find.byKey(body)).height, bodyHeight);
    }

    await expectHeight(120, 120);
    await tester.pumpWidget(const SizedBox());
    phase.value = ForumHtmlBodyLayoutPhase.preparing;
    await expectHeight(20, 120);
    await expectHeight(160, 160);
    phase.value = ForumHtmlBodyLayoutPhase.failed;
    await expectHeight(40, 40);
    phase.value = ForumHtmlBodyLayoutPhase.preparing;
    await expectHeight(20, 120);
    await pumpBody(20, revision: 2);
    expect(tester.getSize(find.byKey(body)).height, 20);
    phase.value = ForumHtmlBodyLayoutPhase.built;
    await expectHeight(96, 96);
    phase.value = ForumHtmlBodyLayoutPhase.preparing;
    await expectHeight(20, 96);
  });

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
