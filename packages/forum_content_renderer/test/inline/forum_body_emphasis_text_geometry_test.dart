import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyEmphasisTextInput _input(
  String html, {
  ForumBodyParagraphLayoutMode mode = ForumBodyParagraphLayoutMode.wrap,
  TextDirection direction = TextDirection.ltr,
}) {
  final doc = const ForumBodyParser().parse(
    html: html,
    sourceId: 'emphasis-geometry',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    doc,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        color: Color(0xff123456),
      ),
      fontRevision: 'emphasis-geometry',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  final content = const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: styles,
    path: '0',
    layoutMode: mode,
  );
  final job = ForumBodyEmphasisTextPreparation(content: content);
  try {
    while (!job.isReady) {
      job.advance(maxParts: 4);
    }
    return job.takeInput();
  } finally {
    job.close();
  }
}

const _html =
    '<p style="text-emphasis:dot red;line-height:.4;text-align:center;">'
    'ffi <b>é</b> 中文 العربية 👩‍👩‍👧‍👦 '
    '<span style="visibility:hidden">隐</span><a href="/synthetic">链</a></p>';

ForumBodyEmphasisTextGeometry _geometry(
  ForumBodyEmphasisTextInput input,
  ForumBodyTextLease base, {
  int quantum = 1,
}) {
  final job = ForumBodyEmphasisGeometryPreparation(
    input: input,
    base: base,
    ensureOwner: () {},
  );
  try {
    var parts = 0;
    while (!job.isReady) {
      final used = job.advance(maxParts: quantum);
      expect(used, inInclusiveRange(1, quantum));
      parts += used;
      expect(parts, lessThan(10000));
    }
    expect(job.advance(maxParts: 1), 0);
    return job.takeGeometry();
  } finally {
    job.close();
  }
}

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.4 : fontSize * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final mode in ForumBodyParagraphLayoutMode.values) {
    for (final dir in TextDirection.values) {
      test('actual whole-base targets $mode $dir without native work', () {
        final input = _input(_html, mode: mode, direction: dir);
        final cache = ForumBodyParagraphCache(
          maxEntries: 2,
          maxEstimatedBytes: 1 << 24,
        );
        final base = cache.acquire(
          content: input.glyphInput.glyphs,
          width: 100,
          textScaler: const _Nonlinear(),
        );
        try {
          final builds = cache.layoutBuildCount;
          final bytes = cache.estimatedRetainedBytes;
          final geometry = _geometry(input, base);
          final batched = _geometry(input, base, quantum: 7);
          expect(geometry.input, same(input));
          expect(geometry.nativeInputIdentity, base.nativeInputIdentity);
          expect(geometry.lineCount, base.layout.lineCount);
          expect(geometry.targets, hasLength(input.units.length));
          expect(cache.layoutBuildCount, builds);
          expect(cache.pictureBuildCount, 0);
          expect(cache.estimatedRetainedBytes, bytes);
          expect(cache.activeLeases, 1);
          for (var i = 0; i < input.units.length; i++) {
            final target = geometry.targets[i], unit = input.units[i];
            final row = base.layout.lines[target.lineIndex];
            expect(target.unit, same(unit));
            expect(
              unit.startUtf16,
              greaterThanOrEqualTo(row.coverageStartUtf16),
            );
            expect(unit.endUtf16, lessThanOrEqualTo(row.coverageEndUtf16));
            expect(target.baseline, row.baseline);
            expect(
              target.boxes,
              base.layout.selectionBoxes(unit.startUtf16, unit.endUtf16),
            );
            final bounds = target.boxes
                .map((box) => box.toRect())
                .reduce((a, b) => a.expandToInclude(b));
            expect(target.fontBounds, bounds);
            expect(target.boxes, batched.targets[i].boxes);
            expect(target.fontBounds, batched.targets[i].fontBounds);
            expect(() => target.boxes.clear(), throwsUnsupportedError);
          }
          expect(() => geometry.targets.clear(), throwsUnsupportedError);
        } finally {
          base.release();
          cache.close();
        }
        expect(cache.activeLeases, 0);
        expect(cache.estimatedRetainedBytes, 0);
      });
    }
  }
  test('native first-line prefix does not shift source target coordinates', () {
    final input = _input(
      '<p style="text-emphasis:dot;text-indent:1em;line-height:.4;">AB CD</p>',
    );
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    final base = cache.acquire(content: input.glyphInput.glyphs, width: 80);
    try {
      final geometry = _geometry(input, base);
      expect(geometry.targets.map((t) => t.unit.startUtf16), [0, 1, 3, 4]);
      expect(geometry.targets.first.lineIndex, 0);
      expect(geometry.targets.first.fontBounds.left, 20);
      expect(geometry.targets[1].fontBounds.left, 40);
      expect(geometry.targets[2].lineIndex, 1);
      expect(geometry.targets[2].fontBounds.left, 0);
      expect(geometry.targets[2].fontBounds.width, 20);
      // Tight line-height does not truncate real font selection geometry.
      expect(geometry.targets.first.fontBounds.height, greaterThan(8));
    } finally {
      base.release();
      cache.close();
    }
  });
  test('native hard/empty lines retain physical row ownership', () {
    final input = _input(
      '<p style="text-emphasis:dot;white-space:pre-wrap;">A<br><br>B<br></p>',
    );
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    final base = cache.acquire(content: input.glyphInput.glyphs, width: 80);
    try {
      final result = _geometry(input, base);
      expect(result.targets.map((t) => t.lineIndex), [0, 2]);
      expect(result.targets.map((t) => t.unit.startUtf16), [0, 3]);
      expect(result.lineCount, 4);
    } finally {
      base.release();
      cache.close();
    }
  });
  test('band child retains local boxes without recording its picture', () {
    final input = _input(
      _html,
      mode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
    );
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    final band = ForumBodyTextBandContent(contexts: [input.glyphInput.glyphs]);
    final base = cache.acquireBandChild(content: band, childIndex: 0);
    try {
      final geometry = _geometry(input, base);
      expect(base.layout.isPaintPrepared, isFalse);
      expect(geometry.lineCount, 1);
      expect(geometry.targets, hasLength(input.units.length));
      for (final target in geometry.targets) {
        expect(target.lineIndex, 0);
        expect(target.baseline, base.layout.alphabeticBaseline);
        expect(
          target.boxes,
          base.layout.selectionBoxes(
            target.unit.startUtf16,
            target.unit.endUtf16,
          ),
        );
      }
      expect(cache.layoutBuildCount, 1);
      expect(cache.pictureBuildCount, 0);
      expect(cache.activeLeases, 1);
    } finally {
      base.release();
      cache.close();
    }
  });
  test('inactive and empty input publish no synthetic targets', () {
    for (final html in ['<p></p>', '<p>plain</p>']) {
      final input = _input(html);
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      final base = cache.acquire(content: input.glyphInput.glyphs, width: 80);
      try {
        expect(_geometry(input, base).targets, isEmpty);
        expect(cache.activeLeases, 1);
      } finally {
        base.release();
        cache.close();
      }
    }
  });
  test('equal-text native input cannot replace the exact derived base', () {
    final input = _input('<p style="text-emphasis:dot;">ffi AB</p>');
    final preparation = ForumBodyEmphasisTextPreparation(
      content: input.content,
    );
    while (!preparation.isReady) {
      preparation.advance(maxParts: 4);
    }
    final other = preparation.takeInput();
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    final base = cache.acquire(content: other.glyphInput.glyphs, width: 100);
    final actual = cache.acquire(content: input.glyphInput.glyphs, width: 100);
    try {
      expect(base.nativeInputIdentity, actual.nativeInputIdentity);
      expect(
        () => ForumBodyEmphasisGeometryPreparation(
          input: input,
          base: base,
          ensureOwner: () {},
        ),
        throwsA(
          isA<ForumBodyEmphasisGeometryException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisGeometryFailure.source,
          ),
        ),
      );
      expect(cache.activeLeases, 2);
      expect(_geometry(input, actual).targets, hasLength(input.units.length));
    } finally {
      base.release();
      actual.release();
      cache.close();
    }
  });
  test(
    'styled grapheme seams keep one original target and every native box',
    () {
      final input = _input(
        '<p style="text-emphasis:dot;">e<b>́</b> '
        '👩‍<small>👩‍👧‍👦</small> 1<span>️⃣</span></p>',
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      final base = cache.acquire(content: input.glyphInput.glyphs, width: 400);
      try {
        final result = _geometry(input, base);
        expect(result.targets, hasLength(3));
        expect(
          result.targets.map(
            (t) => input.content.projection.text.substring(
              t.unit.startUtf16,
              t.unit.endUtf16,
            ),
          ),
          ['é', '👩‍👩‍👧‍👦', '1️⃣'],
        );
        for (final target in result.targets) {
          expect(target.boxes, isNotEmpty);
          expect(target.fontBounds.width, greaterThan(0));
        }
      } finally {
        base.release();
        cache.close();
      }
    },
  );
  for (final retirement in ['lease', 'cache', 'generation']) {
    for (final ready in [false, true]) {
      test('retire $retirement ready=$ready forbids late delivery', () {
        final input = _input(_html);
        final cache = ForumBodyParagraphCache(
          maxEntries: 1,
          maxEstimatedBytes: 1 << 20,
        );
        final base = cache.acquire(
          content: input.glyphInput.glyphs,
          width: 100,
        );
        var current = true;
        final job = ForumBodyEmphasisGeometryPreparation(
          input: input,
          base: base,
          ensureOwner: () {
            if (!current) throw StateError('Retired generation');
          },
        );
        try {
          if (ready) {
            while (!job.isReady) {
              job.advance(maxParts: 4);
            }
          } else {
            job.advance(maxParts: 1);
          }
          switch (retirement) {
            case 'lease':
              base.release();
            case 'cache':
              cache.close();
            case 'generation':
              current = false;
          }
          expect(
            ready ? job.takeGeometry : () => job.advance(maxParts: 1),
            throwsStateError,
          );
          expect(job.takeGeometry, throwsStateError);
          if (retirement == 'generation') expect(cache.activeLeases, 1);
        } finally {
          job.close();
          base.release();
          cache.close();
        }
      });
    }
  }
  test('limits and cancellation keep the borrowed base alive', () {
    final input = _input(_html);
    final cache = ForumBodyParagraphCache(
      maxEntries: 1,
      maxEstimatedBytes: 1 << 20,
    );
    final base = cache.acquire(content: input.glyphInput.glyphs, width: 100);
    final job = ForumBodyEmphasisGeometryPreparation(
      input: input,
      base: base,
      ensureOwner: () {},
      maxBoxes: 0,
    );
    try {
      expect(() => job.advance(maxParts: 0), throwsArgumentError);
      expect(job.takeGeometry, throwsStateError);
      // A failed take retires the partial transaction, not the base handle.
      expect(() => job.advance(maxParts: 1), throwsStateError);
      final limited = ForumBodyEmphasisGeometryPreparation(
        input: input,
        base: base,
        ensureOwner: () {},
        maxBoxes: 0,
      );
      expect(
        () => limited.advance(maxParts: 10),
        throwsA(
          isA<ForumBodyEmphasisGeometryException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisGeometryFailure.limit,
          ),
        ),
      );
      limited.close();
      expect(cache.activeLeases, 1);
      expect(base.layout.isDisposed, isFalse);
    } finally {
      job.close();
      base.release();
      cache.close();
    }
  });
  test('owner callback cancellation and reentry cannot publish a snapshot', () {
    final input = _input(_html);
    final cache = ForumBodyParagraphCache(
      maxEntries: 1,
      maxEstimatedBytes: 1 << 20,
    );
    final base = cache.acquire(content: input.glyphInput.glyphs, width: 100);
    ForumBodyEmphasisGeometryPreparation? job;
    var action = 0;
    job = ForumBodyEmphasisGeometryPreparation(
      input: input,
      base: base,
      ensureOwner: () {
        if (action == 1) job!.close();
        if (action == 2) job!.advance(maxParts: 1);
      },
    );
    try {
      action = 2;
      expect(() => job!.advance(maxParts: 1), throwsStateError);
      job.close();
      action = 0;
      job = ForumBodyEmphasisGeometryPreparation(
        input: input,
        base: base,
        ensureOwner: () {
          if (action == 1) job!.close();
        },
      );
      action = 1;
      expect(() => job!.advance(maxParts: 1), throwsStateError);
      expect(job.isReady, isFalse);
      expect(cache.activeLeases, 1);
    } finally {
      job?.close();
      base.release();
      cache.close();
    }
  });
}
