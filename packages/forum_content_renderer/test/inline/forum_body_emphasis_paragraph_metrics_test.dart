import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _body =
    '<span style="text-emphasis:none;font-size:31px">大</span>AB '
    '<span style="font-size:31px">؀</span>'
    '<span style="text-emphasis-position:under">A</span> '
    'e<b style="font-size:31px">́</b> '
    '<span style="text-emphasis-position:under">👩‍👩‍👧‍👦</span> 中\n\n';

class _Scaler extends TextScaler {
  const _Scaler(this.callback);
  final double Function(double) callback;
  @override
  double scale(double size) => callback(size);
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyParagraphContent _content({
  String body = _body,
  String height = '.4',
  TextDirection direction = TextDirection.ltr,
  bool indent = false,
}) {
  final doc = const ForumBodyParser().parse(
    html:
        '<p style="white-space:pre-wrap;line-height:$height;'
        'text-emphasis:\'X\' red">$body</p>',
    sourceId: 'emphasis-paragraph',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: doc,
    path: '0',
    styles: const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: Color(0xff123456),
        ),
        fontRevision: 'emphasis-paragraph-ahem',
        linkColor: const Color(0xff0000ff),
        textDirection: direction,
        firstLineIndent: ForumBodyLength(
          indent ? 2 : 0,
          ForumBodyLengthUnit.em,
        ),
      ),
    ),
  );
}

ForumBodyParagraphCache _cache({int entries = 32}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 24,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyEmphasisParagraphMetrics _finish(
  ForumBodyEmphasisParagraphPreparation job, {
  bool cachedOnly = false,
}) {
  addTearDown(job.close);
  for (var n = 0; !job.isReady && n < 200000; n++) {
    final s = job.advance(maxParts: 1, cachedOnly: cachedOnly);
    expect(s.partsPrepared, lessThanOrEqualTo(1));
    expect(s.nativeLayoutsBuilt, lessThanOrEqualTo(1));
    expect(s.picturesRecorded, 0);
    expect(s.waitingForLayoutBudget, isFalse);
    expect(job.cacheMiss, isFalse);
  }
  expect(job.isReady, isTrue);
  return job.takeMetrics();
}

void _checkSource(ForumBodyEmphasisParagraphMetrics plan) {
  final text = StringBuffer();
  var offset = 0, start = 0, top = 0.0, marks = 0;
  for (final group in plan.groups) {
    expect(group.top, top);
    expect(group.startLine, start);
    expect(group.startUtf16, offset);
    final source = group.allocation.source.rowInput!;
    expect(source.parentGlyphInput, same(plan.glyphInput));
    expect(group.allocation.reference, same(plan.reference));
    expect(
      source.text.content.projection.text,
      plan.content.projection.text.substring(group.startUtf16, group.endUtf16),
    );
    text.write(source.text.content.projection.text);
    expect(plan.lines[group.startLine].canBreakBefore, isTrue);
    expect(plan.lines[group.endLine - 1].canBreakAfter, isTrue);
    final view = plan.fragment(group.startLine, group.endLine);
    expect(view.startGroup, plan.groups.indexOf(group));
    expect(view.top, group.top);
    expect(view.height, closeTo(group.height, 1e-10));
    expect(view.coverageStartUtf16, group.startUtf16);
    expect(view.coverageEndUtf16, group.endUtf16);
    for (var line = group.startLine; line < group.endLine; line++) {
      final original = plan.reference.naturalLines[line],
          actual = plan.lines[line];
      expect(
        (
          actual.startUtf16,
          actual.endUtf16,
          actual.coverageStartUtf16,
          actual.coverageEndUtf16,
        ),
        (
          original.startUtf16,
          original.endUtf16,
          original.coverageStartUtf16,
          original.coverageEndUtf16,
        ),
      );
      expect(
        (
          actual.engineStartUtf16,
          actual.engineEndUtf16,
          actual.engineCoverageStartUtf16,
          actual.engineCoverageEndUtf16,
        ),
        (
          original.engineStartUtf16,
          original.engineEndUtf16,
          original.engineCoverageStartUtf16,
          original.engineCoverageEndUtf16,
        ),
      );
      expect(
        actual.unpaintedTrailingSpaceStartUtf16,
        original.unpaintedTrailingSpaceStartUtf16,
      );
      expect(actual.canBreakBefore, original.canBreakBefore);
      expect(actual.canBreakAfter, original.canBreakAfter);
      if (line > group.startLine) {
        expect(
          () => plan.fragment(line, group.endLine),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
        expect(
          () => plan.fragment(group.startLine, line),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
      }
    }
    offset = group.endUtf16;
    start = group.endLine;
    top += group.height;
    marks += group.allocation.marks.length;
  }
  expect(text.toString(), plan.content.projection.text);
  expect(start, plan.lines.length);
  expect(marks, plan.markCount);
  if (plan.groups.isNotEmpty) expect(plan.height, top);
  expect(plan.retainedTextCodeUnits, plan.content.projection.text.length * 3);
  expect(plan.retainedRuns, plan.content.runs.length * 2);
  expect(() => plan.lines.clear(), throwsUnsupportedError);
  expect(() => plan.groups.clear(), throwsUnsupportedError);
  expect(() => plan.effectiveScales.clear(), throwsUnsupportedError);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final width in [1.0, 140.0]) {
      for (final height in ['.4', '1.6', '37px']) {
        test('whole source plan $direction width=$width height=$height', () {
          final cache = _cache(),
              content = _content(
                direction: direction,
                height: height,
                indent: true,
              );
          final plan = _finish(
            ForumBodyEmphasisParagraphPreparation(
              content: content,
              cache: cache,
              ensureOwner: () {},
              width: width,
              textScaler: _Scaler(
                (size) => size < 20 ? size * 1.4 : size * 1.1,
              ),
            ),
          );
          expect(cache.activeLeases, 0);
          expect(cache.pictureBuildCount, 0);
          expect(plan.content, same(content));
          _checkSource(plan);
          if (width == 1) {
            expect(plan.groups.any((g) => g.endLine - g.startLine > 1), isTrue);
          }
          expect(plan.lineWindow(ForumBodyParagraphWindow.full), (
            startLine: 0,
            endLine: plan.lines.length,
          ));
          final native = cache.acquire(
            content: plan.glyphInput.glyphs,
            width: width,
            textScaler: plan.textScaler,
          );
          expect(plan.hasTerminalEmptyLine, native.layout.hasTerminalEmptyLine);
          if (plan.hasTerminalEmptyLine) {
            expect(
              plan.lineWindow(ForumBodyParagraphWindow.terminalEmptyLine),
              (startLine: plan.lines.length - 1, endLine: plan.lines.length),
            );
          } else {
            expect(
              () => plan.lineWindow(ForumBodyParagraphWindow.terminalEmptyLine),
              throwsA(isA<ForumBodyParagraphLayoutException>()),
            );
          }
          native.release();
          cache.close();
          _checkSource(plan);
        });
      }
    }
  }
  test('captures caller scales once and produces no measurement pictures', () {
    final cache = _cache(), counts = <double, int>{}, content = _content();
    final plan = _finish(
      ForumBodyEmphasisParagraphPreparation(
        content: content,
        cache: cache,
        ensureOwner: () {},
        width: 140,
        textScaler: _Scaler((size) {
          counts.update(size, (n) => n + 1, ifAbsent: () => 1);
          return size;
        }),
      ),
    );
    expect(counts.values, everyElement(1));
    expect(counts.keys.toSet(), {10.0, 15.5, 20.0, 31.0});
    expect(plan.effectiveScales.keys.toSet(), counts.keys.toSet());
    expect(cache.pictureBuildCount, 0);
    expect(cache.activeLeases, 0);
  });

  test(
    'long paragraph retains all groups beyond the per-group marker limit',
    () {
      final cache = _cache();
      final plan = _finish(
        ForumBodyEmphasisParagraphPreparation(
          content: _content(body: List.filled(600, 'A').join('\n')),
          cache: cache,
          ensureOwner: () {},
          width: 140,
        ),
      );
      expect(plan.markCount, 600);
      expect(plan.groups, hasLength(600));
      expect(plan.lines, hasLength(600));
      expect(cache.layoutBuildCount, 3);
      expect(cache.pictureBuildCount, 0);
      expect(cache.activeLeases, 0);
      _checkSource(plan);
    },
  );

  test(
    'cached-only cold miss resumes and warmed complete plan has no native work',
    () {
      final cache = _cache(), content = _content();
      final first = ForumBodyEmphasisParagraphPreparation(
        content: content,
        cache: cache,
        ensureOwner: () {},
        width: 140,
      );
      for (var n = 0; !first.cacheMiss && n < 20000; n++) {
        first.advance(maxParts: 1, cachedOnly: true);
      }
      expect(first.cacheMiss, isTrue);
      expect(cache.layoutBuildCount, 0);
      expect(cache.pictureBuildCount, 0);
      final a = _finish(first);
      final builds = cache.layoutBuildCount;
      final b = _finish(
        ForumBodyEmphasisParagraphPreparation(
          content: content,
          cache: cache,
          ensureOwner: () {},
          width: 140,
        ),
        cachedOnly: true,
      );
      expect(cache.layoutBuildCount, builds);
      expect(cache.pictureBuildCount, 0);
      expect(b.height, a.height);
      expect(b.markCount, a.markCount);
      _checkSource(b);
    },
  );

  test(
    'isolated clearance retries the whole numeric plan while keeping natural layout',
    () {
      final cache = _cache(), content = _content();
      final plan = _finish(
        ForumBodyEmphasisParagraphPreparation(
          content: content,
          cache: cache,
          ensureOwner: () {},
          width: 1,
          rowIsolationPitch: 8,
        ),
      );
      expect(plan.reference.rowIsolationPitch, greaterThan(8));
      expect(cache.layoutBuildCount, greaterThan(3));
      expect(cache.pictureBuildCount, 0);
      expect(cache.activeLeases, 0);
      _checkSource(plan);
    },
  );

  test(
    'pure paragraph groups rebind current local sources after original cache closes',
    () {
      final cache = _cache(), content = _content();
      final plan = _finish(
        ForumBodyEmphasisParagraphPreparation(
          content: content,
          cache: cache,
          ensureOwner: () {},
          width: 1,
        ),
      );
      cache.close();
      final current = _cache();
      final copied = StringBuffer();
      for (final group in plan.groups) {
        final allocation = group.allocation;
        final job = ForumBodyEmphasisAllocatedPreparation(
          input: allocation.source.rowInput!,
          allocation: allocation,
          cache: current,
          ensureOwner: () {},
          width: 1,
          expectedTextScaler: plan.textScaler,
        );
        addTearDown(job.close);
        for (var n = 0; !job.isReady && n < 50000; n++) {
          final step = job.advance(maxParts: 1);
          expect(
            step.nativeLayoutsBuilt + step.picturesRecorded,
            lessThanOrEqualTo(1),
          );
          expect(step.waitingForLayoutBudget, isFalse);
        }
        expect(job.isReady, isTrue);
        final visible = job.takeLayout();
        try {
          copied.write(visible.projection.text);
          for (final mark in allocation.marks) {
            final unit = allocation
                .source
                .input
                .units[allocation.source.marks[mark.markIndex].unitIndex];
            final full = content.projection.sourceAtUtf16(
              group.startUtf16 + unit.governingUtf16,
            );
            expect(
              visible.sourceAt(mark.fontBounds.center).sourceRune,
              full.sourceRune,
            );
          }
          for (final box in visible.selectionBoxes(
            0,
            visible.projection.text.length,
          )) {
            expect(box.top, greaterThanOrEqualTo(-1e-8));
            expect(box.bottom, lessThanOrEqualTo(group.height + 1e-8));
          }
        } finally {
          visible.close();
        }
        expect(current.activeLeases, 0);
      }
      expect(copied.toString(), content.projection.text);
    },
  );

  test(
    'empty native paragraph retains its real strut without a synthetic row',
    () {
      final cache = _cache(), content = _content(body: '');
      final plan = _finish(
        ForumBodyEmphasisParagraphPreparation(
          content: content,
          cache: cache,
          ensureOwner: () {},
          width: 140,
        ),
      );
      expect(plan.groups, isEmpty);
      expect(plan.lines, isEmpty);
      expect(plan.markCount, 0);
      expect(plan.height, greaterThan(0));
      expect(plan.hasTerminalEmptyLine, isFalse);
      expect(plan.height, plan.reference.naturalHeight);
      expect(plan.alphabeticBaseline, plan.reference.naturalBaseline);
      expect(() => plan.fragment(0, 0), throwsRangeError);
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
    },
  );

  test('font footprint uses complete parents even for one measured group', () {
    final cache = _cache(), content = _content();
    final plan = _finish(
      ForumBodyEmphasisParagraphPreparation(
        content: content,
        cache: cache,
        ensureOwner: () {},
        width: 1,
      ),
    );
    final group = plan.groups[1];
    final counters = (
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.hitCount,
    );
    final slots = plan
        .nativeFootprintFor(group.startLine, group.endLine)
        .toList();
    final parents = slots
        .where((s) => s.request is ForumBodyParagraphTextRequest)
        .toList();
    expect(parents, hasLength(4));
    for (final parent in parents) {
      expect(parent.minimumLineCount, plan.lines.length);
      expect(
        (parent.request as ForumBodyParagraphTextRequest).content.projection,
        same(content.projection),
      );
    }
    expect((
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.hitCount,
    ), counters);
  });

  for (final declared in [false, true]) {
    test(
      'declared owned prefix versus unrelated pin pressure declared=$declared',
      () {
        final cache = _cache(entries: 3), content = _content(body: 'AB CD');
        final extra = cache.acquire(
          content: ForumBodyParagraphContent.anonymousInline(
            identity: content.identity,
            fontRevision: 'prefix',
            styleRevision: content.styleRevision,
            style: content.style.withTextEmphasis(
              const ForumBodyTextEmphasis(),
            ),
          ),
          width: 140,
        );
        final job = ForumBodyEmphasisParagraphPreparation(
          content: content,
          cache: cache,
          ensureOwner: () {},
          width: 140,
          additionalOwnedLeases: declared ? () => [extra] : null,
        );
        if (declared) {
          expect(
            () => _finish(job),
            throwsA(
              isA<ForumBodyParagraphBudgetException>().having(
                (e) => e.failure,
                'failure',
                ForumBodyParagraphBudgetFailure.content,
              ),
            ),
          );
          expect(cache.activeLeases, 1);
          expect(extra.isActive, isTrue);
        } else {
          var waiting = false;
          for (var n = 0; !waiting && n < 30000; n++) {
            waiting = job.advance(maxParts: 1).waitingForLayoutBudget;
          }
          expect(waiting, isTrue);
          final builds = cache.layoutBuildCount;
          for (var n = 0; n < 3; n++) {
            expect(job.advance(maxParts: 1).waitingForLayoutBudget, isTrue);
          }
          expect(cache.layoutBuildCount, builds);
          extra.release();
          final plan = _finish(job);
          expect(plan.markCount, 4);
        }
        extra.release();
        expect(cache.activeLeases, 0);
      },
    );
  }

  test('own parent manifest rejects before shaping', () {
    final cache = _cache(entries: 1), content = _content();
    expect(
      () => _finish(
        ForumBodyEmphasisParagraphPreparation(
          content: content,
          cache: cache,
          ensureOwner: () {},
          width: 140,
        ),
      ),
      throwsA(
        isA<ForumBodyParagraphBudgetException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyParagraphBudgetFailure.content,
        ),
      ),
    );
    expect(cache.layoutBuildCount, 0);
    expect(cache.activeLeases, 0);
  });

  for (final target in [1, 2, 3]) {
    for (final closeCache in [false, true]) {
      test('retirement after native acquisition $target cache=$closeCache', () {
        final cache = _cache(), content = _content(body: 'AB CD');
        var armed = false;
        late ForumBodyEmphasisParagraphPreparation job;
        void owner() {
          if (armed && cache.layoutBuildCount == target) {
            if (closeCache) {
              cache.close();
            } else {
              job.close();
            }
          }
        }

        job = ForumBodyEmphasisParagraphPreparation(
          content: content,
          cache: cache,
          ensureOwner: owner,
          width: 140,
        );
        armed = true;
        expect(() => _finish(job), throwsStateError);
        expect(cache.activeLeases, 0);
        expect(job.nativeLeases, isEmpty);
      });
    }
  }

  for (final cut in [0, 5, 20, 80, 200, 500, 1000]) {
    test('cancellation retires owned prefix at cooperative part $cut', () {
      final cache = _cache();
      final job = ForumBodyEmphasisParagraphPreparation(
        content: _content(),
        cache: cache,
        ensureOwner: () {},
        width: 1,
      );
      for (var part = 0; part < cut && !job.isReady; part++) {
        job.advance(maxParts: 1);
      }
      job.close();
      job.close();
      expect(cache.activeLeases, 0);
      expect(job.nativeLeases, isEmpty);
      expect(job.takeMetrics, throwsStateError);
    });
  }

  test(
    'scaler callback retirement and reentrant advancement release resources',
    () {
      final cache = _cache(), content = _content();
      late ForumBodyEmphasisParagraphPreparation job;
      job = ForumBodyEmphasisParagraphPreparation(
        content: content,
        cache: cache,
        ensureOwner: () {},
        width: 140,
        textScaler: _Scaler((size) {
          job.close();
          return size;
        }),
      );
      expect(() => _finish(job), throwsStateError);
      expect(cache.activeLeases, 0);
      late ForumBodyEmphasisParagraphPreparation reentrant;
      reentrant = ForumBodyEmphasisParagraphPreparation(
        content: content,
        cache: cache,
        ensureOwner: () {},
        width: 140,
        textScaler: _Scaler((size) {
          reentrant.advance();
          return size;
        }),
      );
      expect(() => _finish(reentrant), throwsStateError);
      expect(cache.activeLeases, 0);
    },
  );

  test('ready metrics cannot transfer after generation retirement', () {
    final cache = _cache();
    var active = true;
    final job = ForumBodyEmphasisParagraphPreparation(
      content: _content(),
      cache: cache,
      ensureOwner: () {
        if (!active) throw StateError('Retired');
      },
      width: 140,
    );
    while (!job.isReady) {
      job.advance(maxParts: 17);
    }
    expect(cache.activeLeases, 0);
    active = false;
    expect(job.takeMetrics, throwsStateError);
    expect(job.isReady, isFalse);
    expect(cache.activeLeases, 0);
  });

  test('row, group, mark and height limits never publish a partial plan', () {
    final cache = _cache(), content = _content();
    for (final job in [
      ForumBodyEmphasisParagraphPreparation(
        content: content,
        cache: cache,
        ensureOwner: () {},
        width: 1,
        maxLines: 1,
      ),
      ForumBodyEmphasisParagraphPreparation(
        content: content,
        cache: cache,
        ensureOwner: () {},
        width: 1,
        maxGroupLines: 1,
      ),
      ForumBodyEmphasisParagraphPreparation(
        content: content,
        cache: cache,
        ensureOwner: () {},
        width: 1,
        maxMarks: 1,
      ),
      ForumBodyEmphasisParagraphPreparation(
        content: content,
        cache: cache,
        ensureOwner: () {},
        width: 1,
        maxHeight: 1,
      ),
    ]) {
      expect(
        () => _finish(job),
        throwsA(
          anyOf(
            isA<ForumBodyParagraphLineFrameException>(),
            isA<ForumBodyParagraphRowException>(),
            isA<ForumBodyEmphasisParagraphException>(),
            isA<ForumBodyEmphasisAllocationException>(),
          ),
        ),
      );
      expect(job.isReady, isFalse);
      expect(job.nativeLeases, isEmpty);
      expect(cache.activeLeases, 0);
    }
    expect(cache.pictureBuildCount, 0);
  });
}
