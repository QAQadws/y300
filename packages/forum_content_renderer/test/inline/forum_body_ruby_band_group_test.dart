import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_pair_fixture.dart';

Future<List<int>> raster(ForumBodyRubyGroupLayout group) async {
  final recorder = ui.PictureRecorder();
  group.paint(Canvas(recorder), const Offset(5.25, 8.5));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(400, 200);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final tiny in [false, true]) {
    test(
      'prepared band pair matches standalone geometry, pixels and source (tiny=$tiny)',
      () async {
        final input = rubyPairInput(
          base: '👨‍👩‍👧‍👦e\u0301',
          annotation: 'xyz',
          baseLineHeight: tiny ? .25 : 1,
          annotationLineHeight: tiny ? .25 : 1,
        );
        final owner = ForumBodyParagraphCache(
          maxEntries: 3,
          maxEstimatedBytes: 1 << 20,
        );
        addTearDown(owner.close);
        final expected = ForumBodyRubyGroupLayout.create(
          cache: owner,
          base: input.base,
          annotation: input.annotation,
          gap: 2,
        );
        addTearDown(expected.close);
        final band = ForumBodyTextBandContent(
          contexts: [input.base, input.annotation],
        );
        final base = owner.acquireBandChild(content: band, childIndex: 0);
        final annotation = owner.acquireBandChild(content: band, childIndex: 1);
        owner.prepareBandChildPaint(base);
        owner.prepareBandChildPaint(annotation);
        final group = ForumBodyRubyGroupLayout.adopt(
          cache: owner,
          baseLease: base,
          annotation: input.annotation,
          annotationLease: annotation,
          gap: 2,
        );
        addTearDown(group.close);
        expect(group.size, expected.size);
        expect(group.baseline, closeTo(expected.baseline, 1e-4));
        expect(group.baseOffset, expected.baseOffset);
        expect(group.annotationOffset, expected.annotationOffset);
        expect(await raster(group), await raster(expected));
        for (final part in ForumBodyRubyPart.values) {
          final boxes = group.selectionBoxes(
            part: part,
            startUtf16: 0,
            endUtf16: 1,
          );
          final original = expected.selectionBoxes(
            part: part,
            startUtf16: 0,
            endUtf16: 1,
          );
          expect(
            boxes.map((item) => item.toRect()),
            original.map((item) => item.toRect()),
          );
          final box = boxes.first;
          final hit = group.sourceAt(
            Offset(box.left + .1, (box.top + box.bottom) / 2),
          );
          expect(hit.part, part);
          expect(
            hit.position.sourceRune,
            part == ForumBodyRubyPart.base ? 0 : 9,
          );
        }
        expect(owner.layoutBuildCount, 3);
        group.close();
        expect(base.isActive, isFalse);
        expect(annotation.isActive, isFalse);
        expect(expected.isActive, isTrue);
      },
    );
  }

  test(
    'unprepared band adoption consumes only provided leases, preserves ready siblings',
    () {
      final input = rubyPairInput();
      final owner = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(owner.close);
      final band = ForumBodyTextBandContent(
        contexts: [input.base, input.annotation],
      );
      final base = owner.acquireBandChild(content: band, childIndex: 0);
      final annotation = owner.acquireBandChild(content: band, childIndex: 1);
      final sibling = owner.acquireBandChild(content: band, childIndex: 0);
      owner.prepareBandChildPaint(base);
      expect(
        () => ForumBodyRubyGroupLayout.adopt(
          cache: owner,
          baseLease: base,
          annotation: input.annotation,
          annotationLease: annotation,
        ),
        throwsStateError,
      );
      expect(base.isActive, isFalse);
      expect(annotation.isActive, isFalse);
      expect(sibling.isActive, isTrue);
      expect(sibling.layout.isPaintPrepared, isTrue);
      expect(owner.activeLeases, 1);
      sibling.release();
    },
  );

  for (final bandBase in [false, true]) {
    test(
      'plain and band child leases can mix without another owner (bandBase=$bandBase)',
      () {
        final input = rubyPairInput();
        final owner = ForumBodyParagraphCache(
          maxEntries: 2,
          maxEstimatedBytes: 1 << 20,
        );
        addTearDown(owner.close);
        final content = bandBase ? input.base : input.annotation;
        final child = owner.acquireBandChild(
          content: ForumBodyTextBandContent(contexts: [content]),
          childIndex: 0,
        );
        owner.prepareBandChildPaint(child);
        final plain = owner.acquire(
          content: bandBase ? input.annotation : input.base,
          width: 100,
        );
        final group = ForumBodyRubyGroupLayout.adopt(
          cache: owner,
          baseLease: bandBase ? child : plain,
          annotation: input.annotation,
          annotationLease: bandBase ? plain : child,
        );
        expect(group.size, const Size(40, 30));
        expect(owner.entryCount, 2);
        group.close();
        expect(owner.activeLeases, 0);
      },
    );
  }

  test(
    'foreign band leases fail and consume the handles without retiring either owner',
    () {
      final input = rubyPairInput();
      final a = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      final b = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(a.close);
      addTearDown(b.close);
      final base = a.acquireBandChild(
        content: ForumBodyTextBandContent(contexts: [input.base]),
        childIndex: 0,
      );
      final annotation = b.acquireBandChild(
        content: ForumBodyTextBandContent(contexts: [input.annotation]),
        childIndex: 0,
      );
      a.prepareBandChildPaint(base);
      b.prepareBandChildPaint(annotation);
      expect(
        () => ForumBodyRubyGroupLayout.adopt(
          cache: a,
          baseLease: base,
          annotation: input.annotation,
          annotationLease: annotation,
        ),
        throwsStateError,
      );
      expect(a.activeLeases, 0);
      expect(b.activeLeases, 0);
      expect(a.isClosed, isFalse);
      expect(b.isClosed, isFalse);
    },
  );

  test(
    '120 unique pairs retain four native entries and independent source handles',
    () {
      final document = const ForumBodyParser().parse(
        html:
            '<p>${[for (var i = 0; i < 120; i++) '<span>b$i</span><span style="font-size:10px">r$i</span>'].join()}</p>',
        sourceId: 'dense-band-groups',
        conversionIdentity: 'none',
      );
      final styles = const ForumBodyStyleResolver().resolve(
        document,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            height: 1,
            color: Color(0xff000000),
          ),
          fontRevision: 'loaded',
          linkColor: const Color(0xff0000ff),
        ),
      );
      final contents = [
        for (var i = 0; i < 240; i++)
          const ForumBodyParagraphContentBuilder().build(
            document: document,
            styles: styles,
            path: '0/$i',
            layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
          ),
      ];
      final bands = [
        for (var start = 0; start < 240; start += 64)
          ForumBodyTextBandContent(
            contexts: contents.sublist(
              start,
              start + 64 < 240 ? start + 64 : 240,
            ),
          ),
      ];
      final owner = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(owner.close);
      final groups = <ForumBodyRubyGroupLayout>[];
      addTearDown(() {
        for (final group in groups) {
          group.close();
        }
      });
      for (var i = 0; i < 120; i++) {
        final index = i * 2;
        final base = owner.acquireBandChild(
          content: bands[index ~/ 64],
          childIndex: index % 64,
        );
        final annotation = owner.acquireBandChild(
          content: bands[index ~/ 64],
          childIndex: index % 64 + 1,
        );
        owner.prepareBandChildPaint(base);
        owner.prepareBandChildPaint(annotation);
        final group = ForumBodyRubyGroupLayout.adopt(
          cache: owner,
          baseLease: base,
          annotation: contents[index + 1],
          annotationLease: annotation,
        );
        groups.add(group);
        expect(
          group.projectionFor(ForumBodyRubyPart.base),
          same(contents[index].projection),
        );
        expect(
          group.projectionFor(ForumBodyRubyPart.annotation),
          same(contents[index + 1].projection),
        );
        final box = group
            .selectionBoxes(
              part: ForumBodyRubyPart.annotation,
              startUtf16: 0,
              endUtf16: 1,
            )
            .first;
        final hit = group.sourceAt(
          Offset(box.left + .1, (box.top + box.bottom) / 2),
        );
        expect(
          hit.position.sourceRune,
          contents[index + 1].projection.sourceAtUtf16(0).sourceRune,
        );
      }
      expect(owner.layoutBuildCount, 4);
      expect(owner.entryCount, 4);
      expect(owner.preparedPictureCount, bands.length);
      expect(owner.pictureBuildCount, bands.length);
      expect(owner.activeLeases, 240);
      groups.first.close();
      expect(groups[1].isActive, isTrue);
      expect(owner.activeLeases, 238);
      owner.close();
      for (final group in groups) {
        expect(group.isActive, isFalse);
        group.close();
      }
      expect(owner.activeLeases, 0);
      expect(owner.estimatedRetainedBytes, 0);
    },
  );
}
