import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_paragraph_view.dart'
    show ForumBodyInlineViewAssembly;

import 'test_support/ruby_tree_emphasis_scene_fixture.dart';

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 20 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Use actual font sizes');
}

ForumBodyInlineSpanContent _content(
  RubyTreeEmphasisSceneFixture f, {
  List<ForumBodyParagraphContent>? contexts,
}) {
  final root = f.input.sourceTree.rootGroup.font.fontStrut;
  final actual =
      contexts ??
      [
        for (final source in f.input.sources)
          if (!source.content.isSourceFree) source.content,
      ];
  return ForumBodyInlineSpanContent.compose(
    identity: root.identity,
    path: root.path,
    fontRevision: root.fontRevision,
    styleRevision: root.styleRevision,
    style: ForumBodyResolvedStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
      role: root.style.role,
      textAlign: TextAlign.center,
      textDirection: f.direction,
    ),
    contexts: actual,
    atomicRanges: [
      (
        startUtf16: 0,
        endUtf16: actual.fold(0, (n, c) => n + c.projection.text.length),
      ),
    ],
  );
}

({
  ForumBodyInlineViewAssembly work,
  ForumBodyInlineParagraphLease parent,
  ForumBodyRubyTreeEmphasisLayout tree,
  ForumBodyRubyRootFontBox root,
})
_open(
  RubyTreeEmphasisSceneFixture f, {
  ForumBodyRubyTreeEmphasisLayout? tree,
  ForumBodyInlineSpanContent? content,
  ForumBodyRubyRootFontBox? root,
  ForumBodyParagraphCache? parentCache,
  double extraHeight = 0,
  bool omitRoot = false,
  bool extraTree = false,
  void Function()? ensureOwner,
}) {
  final visible = tree ?? f.finish(f.open());
  final font = f.plan.placement.input.input.geometry.metrics.root.font;
  final actualRoot =
      root ??
      ForumBodyRubyRootFontBox(
        input: f.input.sourceTree.rootGroup.font,
        height: font.height,
        alphabeticBaseline: font.alphabeticBaseline,
      );
  final cache = parentCache ?? f.cache;
  final parent = cache.acquireInline(
    content: content ?? _content(f),
    width: 300,
    textScaler: f.scaler,
    dimensions: [
      PlaceholderDimensions(
        size: Size(visible.size.width, visible.size.height + extraHeight),
        alignment: ui.PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        baselineOffset: visible.baseline,
      ),
    ],
  );
  return (
    parent: parent,
    tree: visible,
    root: actualRoot,
    work: ForumBodyInlineViewAssembly(
      cache: cache,
      parent: parent,
      startLine: 0,
      endLine: parent.layout.lines.length,
      rubyEmphasisTrees: {0: visible, if (extraTree) 1: visible},
      rootFonts: {if (!omitRoot) 0: actualRoot},
      ensureOwner: ensureOwner,
    ),
  );
}

ForumBodyInlineParagraphView _finish(
  ForumBodyInlineViewAssembly work, {
  int quantum = 1,
}) {
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(10000));
      expect(work.advance(maxParts: quantum), inInclusiveRange(1, quantum));
    }
    return work.takeView();
  } finally {
    work.close();
  }
}

Future<List<int>> _pixels(void Function(Canvas) paint, int dpr) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(dpr.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(360 * dpr, 260 * dpr);
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
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Curve()]) {
      for (final (index, html) in [
        rubyTreeEmphasisSceneNested,
        rubyTreeEmphasisSceneMixed,
        rubyTreeEmphasisSceneSegment,
        '<ruby style="text-emphasis:circle">.<rt>x</rt></ruby>',
        if (direction == TextDirection.rtl)
          '<ruby style="text-emphasis:\'X\' red"><rb>'
              '<span dir="rtl" style="font-size:26px">e</span>'
              '<span style="font-size:32px;text-emphasis:\'Y\' blue">́</span>'
              '</rb><rt>x</rt></ruby>',
      ].indexed) {
        test(
          'parent binds actual original windows fixture=$index $direction $scaler',
          () {
            final f = RubyTreeEmphasisSceneFixture(
              html,
              direction: direction,
              scaler: scaler,
            );
            final input = _open(f);
            final before = (
              f.cache.layoutBuildCount,
              f.cache.pictureBuildCount,
            );
            final fragment = input.parent.layout.fragment(
              0,
              input.parent.layout.lines.length,
            );
            final origin =
                input.parent.layout.atomBoxes.single.toRect().topLeft -
                Offset(0, fragment.top);
            final outer = input.root.enclose(
              childSize: input.tree.size,
              childBaseline: input.tree.baseline,
            );
            final view = _finish(input.work, quantum: index + 1);
            try {
              expect(view.content, same(input.parent.content));
              expect(view.nativeLeases.length, f.plan.retainedHandleCount + 1);
              expect(view.atomIndices, [0]);
              for (final source in input.tree.sources) {
                final current = source.source;
                if (current.content.isSourceFree) continue;
                final window = view.content.contexts.singleWhere(
                  (w) => identical(w.content, current.content),
                );
                final length = current.content.projection.text.length;
                for (final painted in [false, true]) {
                  final expected = input.tree
                      .selectionBoxes(
                        sourceId: current.id,
                        startUtf16: 0,
                        endUtf16: length,
                        paintedOnly: painted,
                      )
                      .map((b) => b.toRect().shift(origin + outer.childOffset))
                      .where((rect) => !rect.isEmpty);
                  final actual = painted
                      ? view.glyphBoxes(window.startUtf16, window.endUtf16)
                      : view.selectionBoxes(window.startUtf16, window.endUtf16);
                  expect(
                    actual.map((b) => b.toRect()),
                    orderedEquals(expected),
                  );
                }
              }
              for (final mark in f.plan.placement.marks) {
                final local = mark.fontBounds.center + input.tree.contentOffset;
                final sourceHit = input.tree.sourceAt(local);
                final hit = view.sourceHitAt(
                  local + outer.childOffset + origin,
                );
                expect(hit.window!.content, same(sourceHit.content));
                expect(hit.position.isExact, isFalse);
                expect(hit.position.sourceRune, sourceHit.position.sourceRune);
                expect(
                  hit.position.displayUtf16,
                  hit.window!.startUtf16 + sourceHit.position.displayUtf16,
                );
              }
              expect(
                view.content.projection.display.text,
                f.input.sources.map((s) => s.content.projection.text).join(),
              );
              expect((
                f.cache.layoutBuildCount,
                f.cache.pictureBuildCount,
              ), before);
            } finally {
              view.close();
            }
            expect(input.tree.isActive, isFalse);
            expect(f.cache.activeLeases, 0);
          },
        );
      }
    }
  }
  for (final dpr in [1, 3]) {
    for (final html in [
      rubyTreeEmphasisSceneNested,
      rubyTreeEmphasisSceneMixed,
    ]) {
      test(
        'parent full scene and all alpha backgrounds preserve native pixels DPR$dpr $html',
        () async {
          final f = RubyTreeEmphasisSceneFixture(
            html,
            scaler: TextScaler.linear(1.3),
          );
          final input = _open(f);
          final fragment = input.parent.layout.fragment(
            0,
            input.parent.layout.lines.length,
          );
          final origin =
              input.parent.layout.atomBoxes.single.toRect().topLeft -
              Offset(0, fragment.top);
          final outer = input.root.enclose(
            childSize: input.tree.size,
            childBaseline: input.tree.baseline,
          );
          final view = _finish(input.work);
          try {
            const offset = Offset(11.3, 12.7);
            final before = (
              f.cache.layoutBuildCount,
              f.cache.pictureBuildCount,
            );
            final actual = await _pixels((c) => view.paint(c, offset), dpr);
            final expected = await _pixels((c) {
              input.tree.paintBackgrounds(
                c,
                offset + origin,
                clip: const Rect.fromLTWH(0, 0, 360, 260),
              );
              c.save();
              try {
                c.clipRect(
                  offset & Size(view.width, view.height),
                  doAntiAlias: false,
                );
                fragment.paintParent(c, offset);
                input.tree.paint(c, offset + origin + outer.childOffset);
              } finally {
                c.restore();
              }
            }, dpr);
            expect(actual, expected);
            expect((
              f.cache.layoutBuildCount,
              f.cache.pictureBuildCount,
            ), before);
          } finally {
            view.close();
          }
        },
      );
    }
  }
  test(
    'equal display/source copies cannot replace the actual original current windows',
    () {
      final f = RubyTreeEmphasisSceneFixture(rubyTreeEmphasisSceneMixed);
      final copies = [
        for (final source in f.input.sources)
          if (!source.content.isSourceFree)
            source.content.displayWindow(
              startUtf16: 0,
              endUtf16: source.content.projection.text.length,
            ),
      ];
      final input = _open(f, content: _content(f, contexts: copies));
      expect(
        () => _finish(input.work),
        throwsA(isA<ForumBodyInlineViewException>()),
      );
      expect(input.tree.isActive, isFalse);
      expect(f.cache.activeLeases, 0);
    },
  );
  test('empty RT windows still require the actual source association', () {
    final f = RubyTreeEmphasisSceneFixture(rubyTreeEmphasisSceneNested);
    final input = _open(
      f,
      content: _content(
        f,
        contexts: [
          for (final source in f.input.sources)
            if (!source.content.isSourceFree &&
                source.content.projection.text.isNotEmpty)
              source.content,
        ],
      ),
    );
    expect(
      () => _finish(input.work),
      throwsA(isA<ForumBodyInlineViewException>()),
    );
    expect(f.cache.activeLeases, 0);
  });
  for (final failure in [
    'missing-root',
    'foreign-root',
    'glyph-root',
    'dimension',
    'extra-tree',
    'foreign-cache',
  ]) {
    test('reject $failure before publishing parent source coverage', () {
      final f = RubyTreeEmphasisSceneFixture(rubyTreeEmphasisSceneNested);
      final other = RubyTreeEmphasisSceneFixture(rubyTreeEmphasisSceneNested);
      final font = f.plan.placement.input.input.geometry.metrics.root.font;
      final root = failure == 'foreign-root'
          ? other.input.sourceTree.rootGroup.font
          : font.input;
      final input = _open(
        f,
        omitRoot: failure == 'missing-root',
        root: ['foreign-root', 'glyph-root'].contains(failure)
            ? ForumBodyRubyRootFontBox(
                input: root,
                height: font.height,
                alphabeticBaseline: font.alphabeticBaseline,
              )
            : null,
        extraHeight: failure == 'dimension' ? 1 : 0,
        extraTree: failure == 'extra-tree',
        parentCache: failure == 'foreign-cache' ? other.cache : null,
      );
      expect(
        () => _finish(input.work),
        throwsA(isA<ForumBodyInlineViewException>()),
      );
      expect(input.tree.isActive, isFalse);
      expect(f.cache.activeLeases, 0);
      expect(other.cache.activeLeases, 0);
    });
  }
  test(
    'every parent binding boundary and ready publication cancels all actual handles',
    () {
      final f = RubyTreeEmphasisSceneFixture(rubyTreeEmphasisSceneMixed);
      final first = _open(f);
      final view = _finish(first.work);
      final count = first.work.workCount;
      view.close();
      for (var boundary = 0; boundary <= count; boundary++) {
        final input = _open(f);
        for (var i = 0; i < boundary && !input.work.isReady; i++) {
          input.work.advance(maxParts: 1);
        }
        input.work.close();
        expect(input.work.nativeLeases, isEmpty);
        expect(input.tree.isActive, isFalse);
        expect(f.cache.activeLeases, 0, reason: 'boundary=$boundary');
      }
    },
  );
  test(
    'persistent scene owner revokes parent backgrounds, hit and selection after transfer',
    () {
      final f = RubyTreeEmphasisSceneFixture(rubyTreeEmphasisSceneMixed);
      var active = true;
      final tree = f.finish(
        f.open(
          visibleOwner: () {
            if (!active) throw StateError('retired');
          },
        ),
      );
      final input = _open(f, tree: tree);
      final view = _finish(input.work);
      try {
        active = false;
        expect(() => view.backgroundSurfaces, throwsStateError);
        expect(() => view.sourceAt(Offset.zero), throwsStateError);
        expect(() => view.selectionBoxes(0, 1), throwsStateError);
        final recorder = ui.PictureRecorder();
        try {
          expect(
            () => view.paintContainerBackgrounds(Canvas(recorder), Offset.zero),
            throwsStateError,
          );
        } finally {
          recorder.endRecording().dispose();
        }
      } finally {
        view.close();
      }
    },
  );
  test(
    'visible owner retirement during parent binding cannot publish late resources',
    () {
      final f = RubyTreeEmphasisSceneFixture(rubyTreeEmphasisSceneMixed);
      var active = true;
      final tree = f.finish(
        f.open(
          visibleOwner: () {
            if (!active) throw StateError('retired');
          },
        ),
      );
      final input = _open(f, tree: tree);
      input.work.advance(maxParts: 1);
      active = false;
      expect(() => _finish(input.work), throwsStateError);
      expect(f.cache.activeLeases, 0);
    },
  );
}
