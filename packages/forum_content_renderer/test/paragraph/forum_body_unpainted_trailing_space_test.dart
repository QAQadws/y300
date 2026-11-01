import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../inline/test_support/mixed_inline_fixture.dart';

ForumBodyReaderStyle _reader(TextDirection direction) => ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 20,
    height: 1.5,
    letterSpacing: .5,
    wordSpacing: 7.5,
    color: Color(0xff000000),
  ),
  fontRevision: 'unpainted-space',
  linkColor: const Color(0xff000000),
  textDirection: direction,
);

ForumBodyParagraphContent _content(
  String text,
  TextDirection direction, {
  double indent = 0,
}) {
  final document = const ForumBodyParser().parse(
    html: '<p style="white-space:pre-wrap;text-indent:${indent}px">$text</p>',
    sourceId: 'unpainted-space',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: const ForumBodyStyleResolver().resolve(
      document,
      _reader(direction),
    ),
    path: '0',
  );
}

Future<Uint8List> _pixels(TextPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder)..translate(20, 20), Offset.zero);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(200, 200);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final ending in ['def', '<br>def', '']) {
      test(
        'only native trailing SPACE loses glyph proof ($direction, $ending)',
        () {
          final content = _content('abc  $ending', direction);
          final cache = ForumBodyParagraphCache(
            maxEntries: 4,
            maxEstimatedBytes: 1 << 20,
          );
          addTearDown(cache.close);
          final lease = cache.acquire(content: content, width: 80);
          final prepared = ForumBodyPreparedTextFragment.paragraph(
            lease: lease,
            startLine: 0,
            endLine: 1,
          );
          try {
            final row = lease.layout.lines.first;
            expect(content.projection.text, startsWith('abc  '));
            expect(row.endUtf16, 5);
            expect(row.unpaintedTrailingSpaceStartUtf16, 3);
            expect(row.engineUnpaintedTrailingSpaceStartUtf16, 3);
            expect(lease.layout.selectionBoxes(3, 5), isNotEmpty);
            expect(prepared.glyphBoxes(3, 5), isEmpty);
            expect(
              prepared.glyphBoxes(0, 5).map((b) => b.toRect()),
              lease.layout.selectionBoxes(0, 3).map((b) => b.toRect()),
            );
            expect(
              prepared.glyphBoxes(5, content.projection.text.length),
              ending.startsWith('<br>') ? isNotEmpty : isEmpty,
            );
            final shifted = row.shift(const Offset(8, 11));
            expect(shifted.unpaintedTrailingSpaceStartUtf16, 3);
            expect(shifted.engineUnpaintedTrailingSpaceStartUtf16, 3);
            expect(cache.layoutBuildCount, 1);
          } finally {
            prepared.close();
          }
          expect(cache.activeLeases, 0);
        },
      );
    }
    test(
      'interior spaces keep their original selection and glyph proof ($direction)',
      () {
        final content = _content('a b', direction);
        final cache = ForumBodyParagraphCache(
          maxEntries: 2,
          maxEstimatedBytes: 1 << 20,
        );
        addTearDown(cache.close);
        final lease = cache.acquire(content: content, width: 200);
        final prepared = ForumBodyPreparedTextFragment.paragraph(
          lease: lease,
          startLine: 0,
          endLine: 1,
        );
        try {
          expect(lease.layout.lines.single.unpaintedTrailingSpaceStartUtf16, 3);
          expect(prepared.glyphBoxes(1, 2), isNotEmpty);
          expect(
            prepared.glyphBoxes(1, 2).map((b) => b.toRect()),
            lease.layout.selectionBoxes(1, 2).map((b) => b.toRect()),
          );
        } finally {
          prepared.close();
        }
      },
    );
    for (final text in [
      '   ',
      'abc\u00a0',
      'abc\u202f',
      'abc\u3000',
      'abc\t',
    ]) {
      test(
        'other whitespace and empty rows retain conservative proof ($direction, ${text.codeUnits})',
        () {
          final content = _content(text, direction);
          final cache = ForumBodyParagraphCache(
            maxEntries: 2,
            maxEstimatedBytes: 1 << 20,
          );
          addTearDown(cache.close);
          final lease = cache.acquire(content: content, width: 300);
          final prepared = ForumBodyPreparedTextFragment.paragraph(
            lease: lease,
            startLine: 0,
            endLine: 1,
          );
          try {
            expect(
              lease.layout.lines.single.unpaintedTrailingSpaceStartUtf16,
              content.projection.text.length,
            );
            expect(
              prepared
                  .glyphBoxes(0, content.projection.text.length)
                  .map((b) => b.toRect()),
              lease.layout
                  .selectionBoxes(0, content.projection.text.length)
                  .map((b) => b.toRect()),
            );
          } finally {
            prepared.close();
          }
        },
      );
    }
    test(
      'mixed parent omission leaves atomic child glyphs intact ($direction)',
      () {
        final input = mixedInlineInput(
          prefix: 'abc  ',
          suffix: 'def',
          paragraphStyle: 'white-space:pre-wrap',
          direction: direction.name,
          reader: _reader(direction),
        );
        final cache = ForumBodyParagraphCache(
          maxEntries: 8,
          maxEstimatedBytes: 1 << 20,
        );
        addTearDown(cache.close);
        final group = ForumBodyRubyGroupLayout.create(
          cache: cache,
          base: input.base,
          annotation: input.annotation,
        );
        final parent = cache.acquireInline(
          content: input.content,
          width: 80,
          dimensions: [group.placeholderDimensions],
        );
        final view = ForumBodyInlineParagraphView.adopt(
          cache: cache,
          parent: parent,
          startLine: 0,
          endLine: parent.layout.lines.length,
          rubyGroups: {0: group},
        );
        final prepared = ForumBodyPreparedTextFragment.inline(view);
        try {
          expect(parent.layout.lines.first.unpaintedTrailingSpaceStartUtf16, 3);
          expect(view.selectionBoxes(3, 5, clipToView: false), isNotEmpty);
          expect(prepared.glyphBoxes(3, 5), isEmpty);
          expect(prepared.glyphBoxes(5, 6), isNotEmpty);
          expect(parent.layout.glyphSelection(5, 6).atoms, isNotEmpty);
        } finally {
          prepared.close();
        }
        expect(cache.activeLeases, 0);
      },
    );
    for (final ending in ['def', '\ndef', '']) {
      for (final effect in [
        'none',
        'background',
        'decoration',
        'shadow',
        'all',
      ]) {
        test(
          'native trailing SPACE has no paint effects ($direction, $ending, $effect)',
          () async {
            final style = _reader(direction).textStyle.copyWith(
              backgroundColor: effect == 'background' || effect == 'all'
                  ? const Color(0xffff0000)
                  : null,
              decoration: effect == 'decoration' || effect == 'all'
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: const Color(0xff0000ff),
              shadows: effect == 'shadow' || effect == 'all'
                  ? [
                      const Shadow(
                        color: Color(0xff00ff00),
                        offset: Offset(1, 0),
                        blurRadius: 1,
                      ),
                    ]
                  : null,
            );
            TextPainter build(bool hidden) => TextPainter(
              text: TextSpan(
                style: style,
                children: [
                  const TextSpan(text: 'abc'),
                  TextSpan(
                    text: '  ',
                    style: hidden
                        ? const TextStyle(
                            color: Color(0x00000000),
                            backgroundColor: Color(0x00000000),
                            decoration: TextDecoration.none,
                            shadows: [],
                          )
                        : null,
                  ),
                  TextSpan(text: ending),
                ],
              ),
              textDirection: direction,
            )..layout(minWidth: 80, maxWidth: 80);
            final original = build(false), hidden = build(true);
            try {
              final originalRows = original.computeLineMetrics(),
                  hiddenRows = hidden.computeLineMetrics();
              expect(
                originalRows.map((m) => (m.width, m.left, m.baseline)),
                hiddenRows.map((m) => (m.width, m.left, m.baseline)),
              );
              final a = await _pixels(original), b = await _pixels(hidden);
              var different = 0;
              for (var i = 0; i < a.length; i++) {
                if (a[i] != b[i]) different++;
              }
              expect(different, 0);
            } finally {
              original.dispose();
              hidden.dispose();
            }
          },
        );
      }
    }
  }
  for (final text in ['abc  def', '😀a  def']) {
    test(
      'native prefix keeps explicit UTF-16 trailing-space coordinates ($text)',
      () {
        final content = _content(text, TextDirection.ltr, indent: 20);
        final cache = ForumBodyParagraphCache(
          maxEntries: 2,
          maxEstimatedBytes: 1 << 20,
        );
        addTearDown(cache.close);
        final lease = cache.acquire(content: content, width: 100);
        try {
          final row = lease.layout.lines.first;
          expect(row.unpaintedTrailingSpaceStartUtf16, 3);
          expect(row.engineUnpaintedTrailingSpaceStartUtf16, 5);
          expect(row.engineEndUtf16, row.endUtf16 + 2);
        } finally {
          lease.release();
        }
      },
    );
  }
  test(
    'a whole fragment preserves breaks between multiple omitted suffixes',
    () {
      final content = _content('abc  <br>def  <br>ghi', TextDirection.ltr);
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final lease = cache.acquire(content: content, width: 200);
      final prepared = ForumBodyPreparedTextFragment.paragraph(
        lease: lease,
        startLine: 0,
        endLine: 3,
      );
      try {
        expect(content.projection.text, 'abc  \ndef  \nghi');
        expect(prepared.glyphBoxes(3, 5), isEmpty);
        expect(prepared.glyphBoxes(9, 11), isEmpty);
        expect(prepared.glyphBoxes(0, 15).map((box) => box.toRect()), [
          for (final range in [(0, 3), (5, 9), (11, 15)])
            ...lease.layout
                .selectionBoxes(range.$1, range.$2)
                .map((box) => box.toRect()),
        ]);
        expect(lease.layout.selectionBoxes(3, 5), isNotEmpty);
        expect(lease.layout.selectionBoxes(9, 11), isNotEmpty);
        expect(cache.layoutBuildCount, 1);
      } finally {
        prepared.close();
      }
    },
  );
}
