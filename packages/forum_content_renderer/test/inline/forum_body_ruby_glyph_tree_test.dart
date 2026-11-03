import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_metrics_preparation.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_layout.dart';

const _nested =
    '<ruby style="text-emphasis:\'X\' red;font-size:24px;line-height:.4">'
    '<rb><ruby><rb>A é 👩‍👩‍👧‍👦</rb><rt> inner </rt></ruby></rb>'
    '<rt> outer </rt></ruby>';
const _segment =
    '<ruby style="text-emphasis:\'X\' red;line-height:.4">'
    '<rb>A</rb><rb>B</rb><rtc><rt rbspan="2"> wide </rt></rtc>'
    '<rtc><rt>a</rt><rt style="text-emphasis:\'Y\' blue">音</rt></rtc></ruby>';
const _plainInline =
    '<ruby><rb>A<ruby>B<rt>b</rt></ruby>C</rb><rt>top</rt></ruby>';

ForumBodyRubyGroupContent _group(String html, TextDirection direction) {
  final doc = const ForumBodyParser().parse(
    html: html,
    sourceId: 'glyph-tree-source',
    conversionIdentity: 'none',
  );
  final flow = ForumBodyTextFlowCursor(
    document: doc,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
      fontRevision: 'glyph-ahem',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  try {
    while (!flow.isComplete) {
      flow.advance(maxEvents: 1);
      if (flow.current case ForumBodyTextFlowInline(:final content)) {
        return content.parts.whereType<ForumBodyInlineFlowRuby>().first.group;
      }
    }
    throw StateError('Fixture has no original ruby');
  } finally {
    flow.close();
  }
}

ForumBodyRubyGlyphTreeInput _input(
  String html, {
  TextDirection direction = TextDirection.ltr,
  double maxWidth = 500,
}) {
  final work = ForumBodyRubyGlyphTreeInputPreparation(
    group: _group(html, direction),
    maxWidth: maxWidth,
    ensureOwner: () {},
  );
  try {
    for (var i = 0; !work.isReady; i++) {
      expect(i, lessThan(20000));
      expect(work.advance(maxParts: 1), inInclusiveRange(1, 1));
    }
    return work.takeInput();
  } finally {
    work.close();
  }
}

ForumBodyParagraphCache _cache() {
  final value = ForumBodyParagraphCache(
    maxEntries: 64,
    maxEstimatedBytes: 1 << 24,
  );
  addTearDown(value.close);
  return value;
}

ForumBodyRubyGlyphTreeMetrics _finish(
  ForumBodyRubyGlyphTreeMetricsPreparation work, {
  bool cachedOnly = false,
}) {
  try {
    for (var i = 0; !work.isReady; i++) {
      expect(i, lessThan(20000));
      final step = work.advance(maxParts: 1, cachedOnly: cachedOnly);
      expect(step.formatUnitsPrepared, lessThanOrEqualTo(1));
      expect(step.layoutsBuilt, lessThanOrEqualTo(1));
      expect(step.picturesBuilt, 0);
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
    }
    expect(work.nativeLeases, isEmpty);
    return work.takeMetrics();
  } finally {
    work.close();
  }
}

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 20 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual size');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final html in [
    _nested,
    _segment,
    '<ruby style="text-emphasis:\'X\' red"><rb></rb><rt>音</rt></ruby>',
  ]) {
    for (final direction in TextDirection.values) {
      for (final nonlinear in [false, true]) {
        test('original source, glyphs and actual stack remain separate '
            '$direction nonlinear=$nonlinear $html', () {
          final input = _input(html, direction: direction), cache = _cache();
          expect(input, isNot(isA<ForumBodyRubyTreeInput>()));
          expect(
            input.sources.map((s) => s.id),
            input.sourceTree.sources.map((s) => s.id),
          );
          for (final source in input.sources) {
            final original = input.sourceTree.sources.firstWhere(
              (s) => s.id == source.id,
            );
            expect(source.content, same(original.content));
            expect(input.sourceForId(source.id), same(source));
            expect(
              source.glyphs.style.textStyle,
              source.content.style.textStyle,
            );
            expect(
              source.glyphs.projection.text,
              source.content.projection.text,
            );
            expect(source.glyphs.identity, source.content.identity);
            expect(source.glyphs.style.textEmphasis.isEnabled, isFalse);
            expect(
              source.glyphs.runs.every((r) => !r.style.textEmphasis.isEnabled),
              isTrue,
            );
            if (!source.content.isSourceFree) {
              expect(source.glyphs.projection, same(source.content.projection));
            }
            if (source.emphasis case final emphasis?) {
              expect(emphasis.content, same(source.content));
              expect(emphasis.glyphInput.glyphs, same(source.glyphs));
              expect(
                source.content.style.textEmphasis.isEnabled ||
                    source.content.runs.any(
                      (r) => r.style.textEmphasis.isEnabled,
                    ),
                isTrue,
              );
              for (final unit in emphasis.units) {
                expect(
                  source.content.projection
                      .sourceAtUtf16(unit.governingUtf16)
                      .displayUtf16,
                  inInclusiveRange(0, source.content.projection.text.length),
                );
              }
            }
            if (source.id >= 0) {
              final node =
                  input.sourceTree.nodes[source.id] as ForumBodyRubyTreeText;
              expect(source.needsNative, node.needsNative);
              if (source.needsNative) {
                expect(
                  input.requestForSource(source.id).content,
                  same(source.glyphs),
                );
              } else {
                expect(
                  () => input.requestForSource(source.id),
                  throwsArgumentError,
                );
              }
              expect(
                source.original,
                same(
                  (input.sourceTree.nodes[source.id] as ForumBodyRubyTreeText)
                      .original,
                ),
              );
            }
          }
          var pictures = 0;
          final old = ui.Picture.onCreate;
          ui.Picture.onCreate = (_) {
            pictures++;
          };
          late ForumBodyRubyGlyphTreeMetrics metrics;
          try {
            metrics = _finish(
              ForumBodyRubyGlyphTreeMetricsPreparation(
                input: input,
                cache: cache,
                ensureOwner: () {},
                textScaler: nonlinear
                    ? const _Nonlinear()
                    : TextScaler.noScaling,
              ),
            );
          } finally {
            ui.Picture.onCreate = old;
          }
          expect(pictures, 0);
          expect(cache.pictureBuildCount, 0);
          expect(cache.activeLeases, 0);
          expect(metrics.input, same(input));
          expect(metrics, isNot(isA<ForumBodyRubyTreeMetrics>()));
          expect(metrics.nodes.length, input.sourceTree.nodes.length);
          expect(metrics.box.bounds.height, greaterThan(0));
          expect(metrics.glyphHandleCount, greaterThan(0));
          final builds = cache.layoutBuildCount;
          for (final source in input.sources.where((s) => s.id >= 0)) {
            final node =
                input.sourceTree.nodes[source.id] as ForumBodyRubyTreeText;
            expect(source.needsNative, node.needsNative);
            if (!source.needsNative) continue;
            final lease = input
                .requestForSource(source.id)
                .acquire(
                  cache,
                  width: input.maxWidth,
                  textScaler: metrics.glyphTextScaler,
                  cachedOnly: true,
                );
            expect(lease, isNotNull);
            try {
              expect(lease!.content, same(source.glyphs));
              expect(lease.layout.projection, same(source.glyphs.projection));
            } finally {
              lease?.release();
            }
          }
          expect(cache.layoutBuildCount, builds);
          expect(
            input
                .sourceTree
                .rootGroup
                .font
                .fontStrut
                .style
                .textEmphasis
                .isEnabled,
            isTrue,
          );
          expect(
            metrics.root.font.input.fontStrut.style.textEmphasis.isEnabled,
            isFalse,
          );
          expect(
            metrics.root.font.input.fontStrut.style.textStyle,
            input.sourceTree.rootGroup.font.fontStrut.style.textStyle,
          );
          cache.clearUnpinned();
          expect(metrics.box.bounds.height, greaterThan(0));
          expect(cache.activeLeases, 0);
        });
      }
    }
  }
  test(
    'trimmed author RT, explicit RT emphasis and base graphemes preserve coordinates',
    () {
      final input = _input(_segment);
      final wide = input.sources.firstWhere(
        (s) => s.content.projection.text == 'wide',
      );
      expect(wide.original.projection.text.trim(), 'wide');
      expect(wide.glyphs.projection, same(wide.content.projection));
      final rt = input.sources.firstWhere(
        (s) => s.content.projection.text == '音',
      );
      expect(rt.emphasis, isNotNull);
      expect(
        rt.emphasis!.content.style.textEmphasis.color,
        const Color(0xff0000ff),
      );
      final nested = _input(_nested);
      final base = nested.sources.firstWhere(
        (s) => s.content.projection.text.contains('é'),
      );
      final text = base.content.projection.text;
      final start = text.indexOf('é');
      expect(
        base.emphasis!.units.any(
          (u) => u.startUtf16 == start && u.endUtf16 == start + 2,
        ),
        isTrue,
      );
      final emoji = text.indexOf('👩‍👩‍👧‍👦');
      expect(
        base.emphasis!.units.any(
          (u) =>
              u.startUtf16 == emoji &&
              u.endUtf16 == emoji + '👩‍👩‍👧‍👦'.length,
        ),
        isTrue,
      );
    },
  );
  test(
    'pure tree projection cannot bypass the original native emphasis guard',
    () {
      final input = _input(_nested), cache = _cache();
      final original = ForumBodyRubyTreeMetricsPreparation(
        input: input.sourceTree,
        cache: cache,
        ensureOwner: () {},
      );
      try {
        expect(
          () {
            while (!original.isReady) {
              original.advance(maxParts: 1);
            }
          },
          throwsA(
            isA<ForumBodyParagraphLayoutException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphLayoutFailure.emphasis,
            ),
          ),
        );
      } finally {
        original.close();
      }
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'real band mapping preserves original bindings and remeasures native keys',
    () {
      final input = _input(
        '<ruby style="text-emphasis:\'X\' red">'
        '<rb>A</rb><rb>B</rb><rt>a</rt><rt>b</rt></ruby>',
      );
      final bases = input.sources.where((s) => s.emphasis != null).toList();
      expect(bases, hasLength(2));
      final band = ForumBodyTextBandContent(
        contexts: bases.map((s) => s.glyphs).toList(),
      );
      final mapped = input.mapGlyphRequests((request) {
        final index = band.contexts.indexOf(request.content);
        return index < 0
            ? request
            : ForumBodyTextRequest.bandChild(band: band, childIndex: index);
      });
      expect(mapped.sourceTree, same(input.sourceTree));
      for (final source in input.sources) {
        expect(mapped.sourceForId(source.id), same(source));
      }
      final cache = _cache();
      final metrics = _finish(
        ForumBodyRubyGlyphTreeMetricsPreparation(
          input: mapped,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      expect(
        mapped.glyphRequests.whereType<ForumBodyTextBandChildRequest>(),
        hasLength(2),
      );
      expect(metrics.glyphHandleCount, 4);
      final probe = cache.createBudgetProbe(captureInputEstimates: true);
      try {
        for (final slot in metrics.nativeGlyphBudgetFootprint) {
          slot.request.includeBudget(
            probe,
            width: slot.width,
            minimumLineCount: slot.minimumLineCount,
            textScaler: metrics.glyphTextScaler,
          );
        }
        expect(probe.snapshotNativeEstimates(), hasLength(3));
      } finally {
        probe.close();
      }
      expect(cache.activeLeases, 0);
      expect(
        () => input.mapGlyphRequests(
          (request) => ForumBodyTextRequest.paragraph(
            input.sources
                .firstWhere((s) => identical(s.glyphs, request.content))
                .content,
          ),
        ),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      final root = input.sourceTree.rootGroup as ForumBodyRubyTreeSegment;
      expect(() => root.spanRanks.values.first.add(99), throwsUnsupportedError);
    },
  );
  test(
    'plain mixed inline source contexts keep their actual existing parent',
    () {
      final input = _input(_plainInline), cache = _cache();
      expect(input.sources.any((s) => s.id < 0), isTrue);
      for (final source in input.sources) {
        expect(source.glyphs, same(source.content));
        expect(source.emphasis, isNull);
        if (source.id < 0) {
          expect(() => input.requestForSource(source.id), throwsArgumentError);
        }
      }
      _finish(
        ForumBodyRubyGlyphTreeMetricsPreparation(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
    },
  );
  test(
    'active mixed inline sources remain gated until their parent format is qualified',
    () {
      final html = _plainInline.replaceFirst(
        '<ruby>',
        '<ruby style="text-emphasis:circle">',
      );
      expect(
        () => _input(html),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );
  test('cold cached-only lookup never shapes a projected tree', () {
    final input = _input(_nested), cache = _cache();
    final work = ForumBodyRubyGlyphTreeMetricsPreparation(
      input: input,
      cache: cache,
      ensureOwner: () {},
    );
    try {
      for (var i = 0; !work.cacheMiss; i++) {
        expect(i, lessThan(20000));
        work.advance(maxParts: 1, cachedOnly: true);
      }
      expect(work.isReady, isFalse);
      expect(cache.layoutBuildCount, 0);
      expect(cache.pictureBuildCount, 0);
    } finally {
      work.close();
    }
    expect(cache.activeLeases, 0);
  });
  test(
    'published input and metrics are immutable and retain no owner callback',
    () {
      var active = true;
      final source = ForumBodyRubyGlyphTreeInputPreparation(
        group: _group(_segment, TextDirection.ltr),
        maxWidth: 500,
        ensureOwner: () {
          if (!active) throw StateError('Retired');
        },
      );
      while (!source.isReady) {
        source.advance(maxParts: 1);
      }
      final input = source.takeInput();
      source.close();
      final cache = _cache();
      final work = ForumBodyRubyGlyphTreeMetricsPreparation(
        input: input,
        cache: cache,
        ensureOwner: () {
          if (!active) throw StateError('Retired');
        },
      );
      final metrics = _finish(work);
      active = false;
      cache.close();
      expect(metrics.box.bounds.height, greaterThan(0));
      expect(input.sources, isNotEmpty);
      expect(() => input.sources.clear(), throwsUnsupportedError);
      expect(() => input.glyphRequests.clear(), throwsUnsupportedError);
      expect(() => metrics.nodes.clear(), throwsUnsupportedError);
      expect(
        () => metrics.effectiveGlyphScales.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test('source retirement at every part cannot publish a late glyph graph', () {
    final group = _group(_nested, TextDirection.ltr);
    final first = ForumBodyRubyGlyphTreeInputPreparation(
      group: group,
      maxWidth: 500,
      ensureOwner: () {},
    );
    var count = 0;
    while (!first.isReady) {
      first.advance(maxParts: 1);
      count++;
    }
    first.close();
    for (var boundary = 0; boundary <= count; boundary++) {
      var active = true;
      final work = ForumBodyRubyGlyphTreeInputPreparation(
        group: group,
        maxWidth: 500,
        ensureOwner: () {
          if (!active) throw StateError('Retired');
        },
      );
      for (var i = 0; i < boundary; i++) {
        work.advance(maxParts: 1);
      }
      active = false;
      expect(
        work.isReady ? work.takeInput : () => work.advance(maxParts: 1),
        throwsStateError,
      );
      expect(work.takeInput, throwsStateError);
      work.close();
    }
  });
  test(
    'metric retirement at every part releases temporary native ownership',
    () {
      final input = _input(_nested);
      final warmup = ForumBodyRubyGlyphTreeMetricsPreparation(
        input: input,
        cache: _cache(),
        ensureOwner: () {},
      );
      var count = 0;
      while (!warmup.isReady) {
        warmup.advance(maxParts: 1);
        count++;
      }
      warmup.close();
      for (var boundary = 0; boundary <= count; boundary++) {
        final cache = _cache();
        var active = true;
        final work = ForumBodyRubyGlyphTreeMetricsPreparation(
          input: input,
          cache: cache,
          ensureOwner: () {
            if (!active) throw StateError('Retired');
          },
        );
        for (var i = 0; i < boundary; i++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(
          work.isReady ? work.takeMetrics : () => work.advance(maxParts: 1),
          throwsStateError,
        );
        work.close();
        expect(cache.activeLeases, 0);
        cache.close();
      }
    },
  );
  test('long original grapheme is prepared one scalar at a time', () {
    final text = 'e${String.fromCharCodes(List.filled(256, 0x301))}';
    final work = ForumBodyRubyGlyphTreeInputPreparation(
      group: _group(
        '<ruby style="text-emphasis:circle"><rb>$text</rb><rt>a</rt></ruby>',
        TextDirection.ltr,
      ),
      maxWidth: 500,
      ensureOwner: () {},
    );
    var steps = 0;
    while (!work.isReady) {
      expect(work.advance(maxParts: 1), 1);
      steps++;
    }
    final input = work.takeInput();
    work.close();
    final source = input.sources.firstWhere(
      (s) => s.content.projection.text == text,
    );
    expect(steps, greaterThan(256));
    expect(source.emphasis!.units, hasLength(1));
    expect(source.emphasis!.units.single.startUtf16, 0);
    expect(source.emphasis!.units.single.endUtf16, text.length);
    expect(source.glyphs.projection, same(source.content.projection));
  });
  test(
    'warm glyph measurements reuse native keys without claiming marker layouts',
    () {
      final input = _input(_nested), cache = _cache();
      final first = _finish(
        ForumBodyRubyGlyphTreeMetricsPreparation(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final second = _finish(
        ForumBodyRubyGlyphTreeMetricsPreparation(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
        cachedOnly: true,
      );
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      expect(second.box.bounds, first.box.bounds);
      expect(second.box.alphabeticBaseline, first.box.alphabeticBaseline);
      expect(second.effectiveGlyphScales, first.effectiveGlyphScales);
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
    },
  );
  test('source publication retirement cannot leak the projected graph', () {
    ForumBodyRubyGlyphTreeInputPreparation? work;
    work = ForumBodyRubyGlyphTreeInputPreparation(
      group: _group(_nested, TextDirection.ltr),
      maxWidth: 500,
      ensureOwner: () {
        if (work?.isReady == true) work!.close();
      },
    );
    expect(() => work!.advance(maxParts: 100000), throwsStateError);
    expect(work.takeInput, throwsStateError);
    work.close();
  });
  test(
    'source and metric owner callbacks cannot reenter or consume partial work',
    () {
      ForumBodyRubyGlyphTreeInputPreparation? source;
      source = ForumBodyRubyGlyphTreeInputPreparation(
        group: _group(_nested, TextDirection.ltr),
        maxWidth: 500,
        ensureOwner: () {
          if (source == null) return;
          expect(source.advance, throwsStateError);
          expect(source.takeInput, throwsStateError);
        },
      );
      while (!source.isReady) {
        source.advance(maxParts: 1);
      }
      final input = source.takeInput();
      source.close();
      final cache = _cache();
      ForumBodyRubyGlyphTreeMetricsPreparation? work;
      work = ForumBodyRubyGlyphTreeMetricsPreparation(
        input: input,
        cache: cache,
        ensureOwner: () {
          if (work == null) return;
          expect(work.advance, throwsStateError);
          expect(work.takeMetrics, throwsStateError);
        },
      );
      _finish(work);
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'empty base owns its font leaf while empty RT owns no glyph request',
    () {
      final input = _input(
        '<ruby style="text-emphasis:circle">'
        '<rb></rb><rt style="text-emphasis:inherit"> \t </rt></ruby>',
      );
      final base = input.sources.first;
      final rt = input.sources.last;
      expect(base.content.projection.text, isEmpty);
      expect(base.needsNative, isTrue);
      expect(input.requestForSource(base.id).content, same(base.glyphs));
      expect(rt.content.projection.text, isEmpty);
      expect(rt.needsNative, isFalse);
      expect(rt.emphasis, isNotNull);
      expect(rt.emphasis!.units, isEmpty);
      expect(() => input.requestForSource(rt.id), throwsArgumentError);
      final cache = _cache();
      final metrics = _finish(
        ForumBodyRubyGlyphTreeMetricsPreparation(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      expect(metrics.glyphHandleCount, 1);
      expect(input.glyphRequests, hasLength(1));
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
    },
  );
  for (final html in [
    '<ruby style="font-size:24px;line-height:.4;background:rgba(255,0,0,.5)">'
        '<rb><ruby><rb>A é</rb><rt>inner</rt></ruby></rb><rt>outer</rt></ruby>',
    '<ruby><rb>A</rb> <rb>B</rb><rtc><rt rbspan="2">wide</rt></rtc>'
        '<rtc><rt>a</rt> <rt>b</rt></rtc></ruby>',
    '<ruby><rb>A</rb>\n<rb>B</rb><rt>a</rt>\n<rt>b</rt></ruby>',
    _plainInline,
    '<ruby><rb></rb><rt> </rt></ruby>',
  ]) {
    for (final direction in TextDirection.values) {
      for (final nonlinear in [false, true]) {
        test('source contexts share actual visible-tree coordinates '
            '$direction nonlinear=$nonlinear $html', () {
          final input = _input(html, direction: direction), cache = _cache();
          final scaler = nonlinear ? const _Nonlinear() : TextScaler.noScaling;
          final metrics = _finish(
            ForumBodyRubyGlyphTreeMetricsPreparation(
              input: input,
              cache: cache,
              ensureOwner: () {},
              textScaler: scaler,
            ),
          );
          final before = (
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.activeLeases,
          );
          final geometry = _geometry(metrics);
          expect((
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.activeLeases,
          ), before);
          expect(geometry.metrics, same(metrics));
          expect(geometry.nodes, hasLength(input.sourceTree.nodes.length));
          expect(
            geometry.nodes.map((n) => n.id).toSet(),
            hasLength(geometry.nodes.length),
          );
          expect(geometry.nodes.first.id, input.sourceTree.root);
          expect(geometry.nodes.first.origin, Offset.zero);
          expect(geometry.nodes.first.parent, isNull);
          expect(geometry.nodes.first.edge, isNull);
          for (final node in geometry.nodes) {
            expect(geometry.nodeForId(node.id), same(node));
            if (node.parent case final parent?) {
              expect(node.edge!.node, node.id);
              expect(node.origin, parent.contentOrigin + node.edge!.offset);
              expect(geometry.nodeForId(parent.id), same(parent));
              expect(
                geometry.nodes.indexOf(parent),
                lessThan(geometry.nodes.indexOf(node)),
              );
            }
          }
          expect(
            geometry.sources.map((s) => s.source),
            orderedEquals(input.sources),
          );

          // Bind the ordinary, originally supported visible format separately.
          // Existing pixel tests additionally guard the shared child offsets.
          final original = ForumBodyRubyTreeMetricsPreparation(
            input: input.sourceTree,
            cache: cache,
            ensureOwner: () {},
            textScaler: scaler,
          );
          while (!original.isReady) {
            original.advance(maxParts: 1);
          }
          final originalMetrics = original.takeMetrics();
          original.close();
          final bind = ForumBodyRubyTreePreparation(
            input: input.sourceTree,
            metrics: originalMetrics,
            cache: cache,
            ensureOwner: () {},
            expectedTextScaler: scaler,
          );
          try {
            while (!bind.isReady) {
              final step = bind.advance(maxParts: 1);
              expect(step.waitingForLayoutBudget, isFalse);
              expect(bind.cacheMiss, isFalse);
            }
            final visible = bind.takeLayout();
            try {
              expect(
                visible.members.map((m) => m.nodeIndex),
                geometry.sources.map((s) => s.source.id),
              );
              for (final member in visible.members) {
                final source = geometry.sourceForId(member.nodeIndex);
                expect(source.source.content, same(member.content));
                expect(source.contextOrigin, member.offset);
                expect(source.usesInlineParent, member.inlineView != null);
                if (member.lease case final lease?) {
                  final local = metrics.nodes[source.node.id].box!;
                  expect(
                    local.bounds,
                    originalMetrics.nodes[source.node.id].box!.bounds,
                  );
                  if (member.content.projection.text.isNotEmpty) {
                    final box = lease.layout
                        .selectionBoxes(
                          0,
                          member.content.projection.text.length,
                        )
                        .first;
                    final hit = visible.sourceAt(
                      box.toRect().center + member.offset,
                    );
                    expect(hit.nodeIndex, member.nodeIndex);
                    expect(hit.content, same(member.content));
                  }
                }
              }
            } finally {
              visible.close();
            }
          } finally {
            bind.close();
          }
          expect(cache.activeLeases, 0);
          cache.close();
          expect(
            geometry.sources.map((s) => s.contextOrigin),
            everyElement(isA<Offset>()),
          );
          expect(() => geometry.nodes.clear(), throwsUnsupportedError);
          expect(() => geometry.sources.clear(), throwsUnsupportedError);
          expect(() => geometry.nodeForId(-1), throwsArgumentError);
          expect(() => geometry.sourceForId(100000), throwsArgumentError);
        });
      }
    }
  }
  test('active source ancestry distinguishes base, RT and spanning ranks', () {
    final cache = _cache();
    ForumBodyRubyGlyphTreeGeometry prepare(String html) {
      final input = _input(html);
      return _geometry(
        _finish(
          ForumBodyRubyGlyphTreeMetricsPreparation(
            input: input,
            cache: cache,
            ensureOwner: () {},
          ),
        ),
      );
    }

    final nested = prepare(_nested);
    final base = nested.sources.firstWhere(
      (s) => s.source.content.projection.text.contains('é'),
    );
    final inner = nested.sources.firstWhere(
      (s) => s.source.content.projection.text == 'inner',
    );
    final outer = nested.sources.firstWhere(
      (s) => s.source.content.projection.text == 'outer',
    );
    List<ForumBodyRubyTreeChildGeometry> path(
      ForumBodyRubyGlyphTreeSourcePosition source,
    ) {
      final edges = <ForumBodyRubyTreeChildGeometry>[];
      for (var node = source.node; node.parent != null; node = node.parent!) {
        edges.add(node.edge!);
      }
      return edges;
    }

    expect(
      path(base).where((e) => e.branch == ForumBodyRubyTreeBranch.base),
      hasLength(2),
    );
    expect(
      path(base).where((e) => e.branch == ForumBodyRubyTreeBranch.annotation),
      isEmpty,
    );
    expect(
      path(inner).where((e) => e.branch == ForumBodyRubyTreeBranch.base),
      hasLength(1),
    );
    expect(
      path(inner).where((e) => e.branch == ForumBodyRubyTreeBranch.annotation),
      hasLength(1),
    );
    expect(
      path(outer).where((e) => e.branch == ForumBodyRubyTreeBranch.base),
      isEmpty,
    );
    expect(
      path(outer).where((e) => e.branch == ForumBodyRubyTreeBranch.annotation),
      hasLength(1),
    );
    expect(base.source.emphasis, isNotNull);
    expect(
      nested
          .metrics
          .input
          .sourceTree
          .rootGroup
          .font
          .fontStrut
          .style
          .textEmphasis
          .isEnabled,
      isTrue,
    );
    final segment = prepare(_segment);
    final rt = segment.sources.firstWhere(
      (s) => s.source.content.projection.text == '音',
    );
    final position = rt.node;
    expect(position.edge!.branch, ForumBodyRubyTreeBranch.span);
    final parent =
        segment.metrics.input.sourceTree.nodes[position.parent!.id]
            as ForumBodyRubyTreeSegment;
    final span = parent.spans[position.edge!.index];
    expect((span.startColumn, span.endColumn, span.rank), (1, 2, 1));
    expect(rt.source.emphasis, isNotNull);
    expect(cache.activeLeases, 0);
    expect(cache.pictureBuildCount, 0);
  });
  test(
    'glyph geometry cancellation and reentry remain bounded through publication',
    () {
      final cache = _cache();
      final metrics = _finish(
        ForumBodyRubyGlyphTreeMetricsPreparation(
          input: _input(_segment),
          cache: cache,
          ensureOwner: () {},
        ),
      );
      var parts = 0;
      final count = ForumBodyRubyGlyphTreeGeometryPreparation(
        metrics: metrics,
        ensureOwner: () {},
      );
      while (!count.isReady) {
        parts += count.advance(maxParts: 1);
      }
      count.close();
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      );
      for (var at = 0; at <= parts; at++) {
        var active = true;
        final work = ForumBodyRubyGlyphTreeGeometryPreparation(
          metrics: metrics,
          ensureOwner: () {
            if (!active) throw StateError('retired');
          },
        );
        for (var i = 0; i < at; i++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(() => work.advance(maxParts: 1), throwsStateError);
        expect(work.takeGeometry, throwsStateError);
        work.close();
        work.close();
      }
      ForumBodyRubyGlyphTreeGeometryPreparation? reentry;
      reentry = ForumBodyRubyGlyphTreeGeometryPreparation(
        metrics: metrics,
        ensureOwner: () {
          if (reentry == null) return;
          expect(reentry.advance, throwsStateError);
          expect(reentry.takeGeometry, throwsStateError);
        },
      );
      while (!reentry.isReady) {
        reentry.advance(maxParts: 1);
      }
      final value = reentry.takeGeometry();
      reentry.close();
      expect(value.sources, hasLength(metrics.input.sources.length));
      ForumBodyRubyGlyphTreeGeometryPreparation? publication;
      publication = ForumBodyRubyGlyphTreeGeometryPreparation(
        metrics: metrics,
        ensureOwner: () {
          if (publication?.isReady == true) publication!.close();
        },
      );
      expect(() => publication!.advance(maxParts: 10000), throwsStateError);
      expect(publication.takeGeometry, throwsStateError);
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      ), before);
    },
  );
  test(
    'wide source trees retain ancestry prefixes without an unbounded final copy',
    () {
      final children = List.generate(80, (i) => '<rb>A$i</rb>').join();
      final input = _input(
        '<ruby>$children<rt rbspan="80">wide</rt></ruby>',
        maxWidth: 8000,
      );
      final cache = _cache();
      final metrics = _finish(
        ForumBodyRubyGlyphTreeMetricsPreparation(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      final geometry = _geometry(metrics);
      final root = geometry.nodes.first;
      final direct = geometry.nodes
          .where((n) => identical(n.parent, root))
          .toList();
      expect(direct, hasLength(81));
      expect(direct.every((n) => identical(n.parent, root)), isTrue);
      expect(geometry.sources, hasLength(81));
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
    },
  );
}

ForumBodyRubyGlyphTreeGeometry _geometry(
  ForumBodyRubyGlyphTreeMetrics metrics,
) {
  final work = ForumBodyRubyGlyphTreeGeometryPreparation(
    metrics: metrics,
    ensureOwner: () {},
  );
  var parts = 0;
  try {
    while (!work.isReady) {
      expect(work.advance(maxParts: 1), 1);
      expect(
        ++parts,
        lessThan(12 * (metrics.nodes.length + metrics.input.sources.length)),
      );
    }
    final result = work.takeGeometry();
    expect(work.takeGeometry, throwsStateError);
    expect(work.advance, throwsStateError);
    return result;
  } finally {
    work.close();
  }
}
