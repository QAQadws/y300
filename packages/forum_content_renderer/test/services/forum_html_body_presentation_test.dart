import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  testWidgets('unchanged body configuration does not relayout its ancestors', (
    tester,
  ) async {
    final presentation = ForumHtmlBodyPresentation();
    final updates = ValueNotifier(0);
    final contentHeight = ValueNotifier(120.0);
    addTearDown(presentation.dispose);
    addTearDown(updates.dispose);
    addTearDown(contentHeight.dispose);
    var layouts = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: _LayoutCounter(
            onLayout: () => layouts++,
            child: ValueListenableBuilder<int>(
              valueListenable: updates,
              child: ValueListenableBuilder<double>(
                valueListenable: contentHeight,
                builder: (_, height, _) => SizedBox(width: 200, height: height),
              ),
              builder: (_, value, child) => ForumHtmlBodyLayout(
                presentation: presentation,
                sourceId: 'body',
                revision: 'layout',
                builder: (ready) {
                  ready();
                  return child!;
                },
              ),
            ),
          ),
        ),
      ),
    );
    final initialLayouts = layouts;
    for (var update = 1; update <= 10; update++) {
      updates.value = update;
      await tester.pump();
    }

    expect(layouts, initialLayouts);
    expect(
      tester.getSize(find.byType(ForumHtmlBodyLayout)),
      const Size(200, 120),
    );
    contentHeight.value = 180;
    await tester.pump();
    expect(layouts, initialLayouts + 1);
    expect(
      tester.getSize(find.byType(ForumHtmlBodyLayout)),
      const Size(200, 180),
    );
  });

  testWidgets('new layout ownership still replaces a pending height hint', (
    tester,
  ) async {
    final first = ForumHtmlBodyPresentation();
    final second = ForumHtmlBodyPresentation();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    for (final sample in [
      (first, 'a', 'old', 80.0),
      (first, 'a', 'new', 120.0),
      (first, 'b', 'new', 160.0),
      (second, 'b', 'new', 200.0),
    ]) {
      sample.$1.recordLayout(sample.$2, (
        sample.$3,
        300.0,
        sample.$1.expansionRevision,
      ), sample.$4);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              child: ForumHtmlBodyLayout(
                presentation: sample.$1,
                sourceId: sample.$2,
                revision: sample.$3,
                builder: (_) => const SizedBox(height: 10),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(ForumHtmlBodyLayout)).height,
        sample.$4,
      );
    }
  });

  testWidgets(
    'readiness alone releases a restored height and records content',
    (tester) async {
      final presentation = ForumHtmlBodyPresentation();
      final updates = ValueNotifier(false);
      addTearDown(presentation.dispose);
      addTearDown(updates.dispose);
      final revision = ('layout', 300.0, presentation.expansionRevision);
      presentation.recordLayout('body', revision, 200);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              child: ValueListenableBuilder<bool>(
                valueListenable: updates,
                builder: (_, complete, child) => ForumHtmlBodyLayout(
                  presentation: presentation,
                  sourceId: 'body',
                  revision: 'layout',
                  builder: (ready) {
                    if (complete) ready();
                    return const SizedBox(height: 120);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ForumHtmlBodyLayout)).height, 200);
      updates.value = true;
      await tester.pump();
      expect(tester.getSize(find.byType(ForumHtmlBodyLayout)).height, 120);
      expect(presentation.heightFor('body', revision), 120);
    },
  );

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

class _LayoutCounter extends SingleChildRenderObjectWidget {
  const _LayoutCounter({required this.onLayout, required super.child});
  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _LayoutCounterBox(onLayout);
}

class _LayoutCounterBox extends RenderProxyBox {
  _LayoutCounterBox(this.onLayout);
  final VoidCallback onLayout;

  @override
  void performLayout() {
    onLayout();
    super.performLayout();
  }
}
