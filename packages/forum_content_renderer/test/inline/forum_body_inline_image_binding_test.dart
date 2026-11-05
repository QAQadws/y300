import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_paragraph_view.dart'
    show ForumBodyInlineViewAssembly;
import 'test_support/inline_image_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a warm native layout binds current image inputs, never cached resource values',
    () {
      final f = InlineImageFixture();
      final old = f.view();
      final updated = {
        for (final e in f.images.entries)
          e.key: ForumBodyInlineImageInput(
            document: f.document,
            element: e.value.element,
            dimensions: e.value.dimensions,
            image: const InlineImageDescription(keyOverride: 'new-cache'),
          ),
      };
      final current = f.view(input: f.content(bindings: updated));
      expect(f.cache.layoutBuildCount, 1);
      expect(current.images[0]!.input, same(updated[0]));
      expect(old.images[0]!.input, same(f.images[0]));
      old.images[0]!.reportDisplayFrame(true);
      expect(current.images[0]!.hasRenderedFrame, isFalse);
      old.close();
      expect(current.isActive, isTrue);
      current.close();
      expect(f.cache.activeLeases, 0);
    },
  );
  test(
    'real single-level ruby and image nodes keep independent visible bindings',
    () {
      final document = const ForumBodyParser().parse(
        html:
            '<p><span>X</span><img src="https://example.invalid/a.png">'
            '<ruby>A<rt>a</rt></ruby><img src="https://example.invalid/a.png"><span>Y</span></p>',
        sourceId: 'ruby-images',
        conversionIdentity: 'none',
      );
      final styles = const ForumBodyStyleResolver().resolve(
        document,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 10,
            height: 1,
          ),
          fontRevision: 'ahem',
          linkColor: const Color(0xff0000ff),
        ),
      );
      ForumBodyParagraphContent text(String path) =>
          const ForumBodyParagraphContentBuilder().build(
            document: document,
            styles: styles,
            path: path,
            layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
          );
      final base = text('0/2/0'), annotation = text('0/2/1/0');
      ForumBodyInlineImageInput image(String path) => ForumBodyInlineImageInput(
        document: document,
        element: document.nodeAtPath(path)! as ForumBodyElement,
        image: const InlineImageDescription(),
        dimensions: inlineImageDimensions(const Size(20, 20)),
      );
      final input = ForumBodyInlineSpanContent.compose(
        identity: document.identity,
        path: '0',
        fontRevision: styles.fontRevision,
        styleRevision: styles.resolverRevision,
        style: styles.byPath['0']!,
        contexts: [text('0/0'), base, annotation, text('0/4')],
        atomicRanges: [
          (startUtf16: 1, endUtf16: 1),
          (startUtf16: 1, endUtf16: 3),
          (startUtf16: 3, endUtf16: 3),
        ],
        resourceAtoms: {0, 2},
        images: {0: image('0/1'), 2: image('0/3')},
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 22,
      );
      addTearDown(cache.close);
      final ruby = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: base,
        annotation: annotation,
      );
      final parent = cache.acquireInline(
        content: input,
        width: 100,
        dimensions: [
          input.images[0]!.dimensions,
          ruby.placeholderDimensions,
          input.images[2]!.dimensions,
        ],
      );
      final view = ForumBodyInlineParagraphView.adopt(
        cache: cache,
        parent: parent,
        startLine: 0,
        endLine: 1,
        rubyGroups: {1: ruby},
      );
      expect(view.images.keys, [0, 2]);
      expect(view.atomIndices, [1]);
      expect(view.nativeLeases, hasLength(3));
      expect(view.content.projection.display.text, 'XAaY');
      final glyphs = view.glyphBoxes(0, 4);
      expect(glyphs, isNotEmpty);
      expect(
        glyphs.any(
          (g) => view.images.values.any((i) => i.rect.overlaps(g.toRect())),
        ),
        isFalse,
      );
      for (final i in view.images.values) {
        expect(view.sourceAt(i.rect.center).isExact, isFalse);
      }
      final recorder = ui.PictureRecorder();
      view.paintTextLayer(Canvas(recorder), Offset.zero);
      recorder.endRecording().dispose();
      view.close();
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'same URL occurrences bind real nodes without text or native child handles',
    () {
      final f = InlineImageFixture();
      final view = f.view();
      final images = view.images.values.toList();
      expect(images.map((i) => i.input.element.path), ['0/1', '0/2']);
      expect(images.map((i) => i.input.image.cacheKey).toSet(), hasLength(1));
      expect(view.content.projection.display.text, 'AB');
      expect(view.nativeLeases, hasLength(1));
      expect(view.atomIndices, isEmpty);
      expect(view.hasRenderedImages, isFalse);
      for (final binding in images) {
        expect(view.imageAt(binding.rect.center), same(binding));
        expect(view.sourceAt(binding.rect.center).isExact, isFalse);
        expect(binding.input.entry, isNull);
        expect(binding.reportDisplayFrame(true), isTrue);
        expect(binding.reportDisplayFrame(true), isFalse);
      }
      expect(view.hasRenderedImages, isTrue);
      final glyphs = view.glyphBoxes(0, 2);
      expect(glyphs, hasLength(2));
      expect(
        glyphs.any((g) => images.any((i) => i.rect.overlaps(g.toRect()))),
        isFalse,
      );
      expect(() => view.images.clear(), throwsUnsupportedError);
      view.close();
      expect(f.cache.activeLeases, 0);
      for (final image in images) {
        expect(image.isActive, isFalse);
        expect(image.hasRenderedFrame, isFalse);
        expect(image.reportDisplayFrame(true), isFalse);
      }
    },
  );
  test(
    'only actual engine-window resources are bound on an image-only row',
    () {
      final f = InlineImageFixture(
        count: 3,
        before: '',
        after: '',
        size: const Size(50, 20),
      );
      final view = f.view(
        startLine: 1,
        endLine: 2,
        input: f.content(bindings: {2: f.images[2]!}),
      );
      expect(view.images.keys, [2]);
      expect(view.images[2]!.lineIndex, 1);
      expect((view.coverageStartUtf16, view.coverageEndUtf16), (0, 0));
      expect(view.glyphBoxes(0, 0), isEmpty);
      expect(view.sourceAt(view.images[2]!.rect.center).isExact, isFalse);
      view.close();
      expect(f.cache.activeLeases, 0);
    },
  );
  test(
    'resource description verifies actual IR object, kind and dimensions',
    () {
      final f = InlineImageFixture();
      final other = const ForumBodyParser().parse(
        html: '<img src="https://example.invalid/a.png">',
        sourceId: 'other',
        conversionIdentity: 'none',
      );
      expect(
        () => ForumBodyInlineImageInput(
          document: f.document,
          element: other.nodes.single as ForumBodyElement,
          image: f.images[0]!.image,
          dimensions: inlineImageDimensions(const Size(20, 20)),
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyInlineImageInput(
          document: f.document,
          element: f.document.nodes.single as ForumBodyElement,
          image: f.images[0]!.image,
          dimensions: inlineImageDimensions(const Size(20, 20)),
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyInlineImageInput(
          document: f.document,
          element: f.images[0]!.element,
          image: f.images[0]!.image,
          dimensions: const PlaceholderDimensions(
            size: Size(20, 20),
            alignment: ui.PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: 21,
          ),
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'duplicate node reuse and a foreign identity fail before native layout',
    () {
      final f = InlineImageFixture(), foreign = InlineImageFixture(before: 'X');
      expect(
        () => f.content(bindings: {0: f.images[0]!, 1: f.images[0]!}),
        throwsArgumentError,
      );
      expect(
        () => f.content(bindings: {0: foreign.images[0]!}),
        throwsArgumentError,
      );
      expect(f.cache.layoutBuildCount, 0);
      expect(
        () => f.content(maxInputCodeUnits: 2),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );
  test(
    'missing resource or different dimensions cannot qualify visible delivery',
    () {
      final f = InlineImageFixture();
      expect(
        () => f.view(input: f.content(bindings: {})),
        throwsA(isA<ForumBodyInlineViewException>()),
      );
      expect(f.cache.activeLeases, 0);
      expect(
        () => f.view(
          dimensions: List.filled(2, inlineImageDimensions(const Size(21, 20))),
        ),
        throwsA(isA<ForumBodyInlineViewException>()),
      );
      expect(f.cache.activeLeases, 0);
    },
  );
  test(
    'text atom repartition retains the original images at remapped indices',
    () {
      final f = InlineImageFixture(), original = f.content();
      final next = original.repartitionAtoms(
        atomicRanges: [
          (startUtf16: 0, endUtf16: 1),
          (startUtf16: 1, endUtf16: 1),
          (startUtf16: 1, endUtf16: 1),
        ],
        softSpaceAtoms: {},
        resourceAtoms: {1, 2},
      );
      expect(next.images[1], same(f.images[0]));
      expect(next.images[2], same(f.images[1]));
      expect(next.projection.display, same(original.projection.display));
    },
  );
  test(
    'image-aware views cannot silently become canvas-only complete scenes',
    () {
      final f = InlineImageFixture();
      final view = f.view();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      expect(
        () => view.paint(canvas, Offset.zero),
        throwsA(isA<ForumBodyInlineViewException>()),
      );
      expect(
        () => view.paintCommands(Offset.zero).toList(),
        throwsA(isA<ForumBodyInlineViewException>()),
      );
      view.paintTextLayer(canvas, Offset.zero);
      recorder.endRecording().dispose();
      view.close();
    },
  );
  test(
    'cooperative resource assembly stays bounded and cancellation releases owner',
    () {
      final f = InlineImageFixture();
      final job = ForumBodyInlineViewAssembly(
        cache: f.cache,
        parent: f.parent(),
        startLine: 0,
        endLine: 1,
      );
      while (job.preparedAtomCount == 0) {
        expect(job.advance(maxParts: 1), lessThanOrEqualTo(1));
      }
      job.close();
      expect(f.cache.activeLeases, 0);
    },
  );
}
