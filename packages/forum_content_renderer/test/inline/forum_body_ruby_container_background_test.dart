import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_preparation.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_atom_request.dart';

ForumBodyInlinePlanInput _input(
  String children, {
  String background = 'rgba(255,0,0,.5)',
  ForumBodyStyleScope scope = ForumBodyStyleScope.asDefault,
}) {
  final document = const ForumBodyParser().parse(
    html:
        '<ruby style="font-size:40px;line-height:3;background:$background">$children</ruby>',
    sourceId: 'container-background',
    conversionIdentity: 'none',
  );
  final flow = ForumBodyTextFlowCursor(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
      policy: ForumBodyStylePolicy({ForumBodyStyleProperty.background: scope}),
    ),
  );
  try {
    while (!flow.isComplete) {
      flow.advance(maxEvents: 1);
      if (flow.current case ForumBodyTextFlowInline(:final content)) {
        return ForumBodyInlinePlanInput(content, 300);
      }
    }
    throw StateError('No inline input');
  } finally {
    flow.close();
  }
}

ForumBodyRubyContainerBackground? _background(ForumBodyRubyAtomRequest atom) =>
    atom.background;
const _column = '<rb style="font-size:20px">A</rb><rt>x</rt>';
const _segment = '<rb>A</rb><rb>B</rb><rtc><rt>x</rt></rtc><rtc>word</rtc>';
const _space = '<rb>A</rb> <rb>B</rb><rt>x</rt> <rt>y</rt>';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'container font admission waits for foreign pins and releases its own temporary lease',
    () {
      final input = _input(_column);
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final foreign = cache.acquire(
        content: input.groups.single.base.content,
        width: 300,
      );
      final job = ForumBodyInlinePlanPreparation(
        input: input,
        cache: cache,
        textScaler: TextScaler.noScaling,
        ensureOwner: () {},
      );
      addTearDown(job.close);
      final builds = cache.layoutBuildCount;
      final blocked = job.advance(maxParts: 1);
      expect(blocked.waitingForLayoutBudget, true);
      expect(blocked.partsPrepared, 0);
      expect(cache.layoutBuildCount, builds);
      expect(foreign.isActive, true);
      foreign.release();
      final captured = job.advance(maxParts: 1);
      expect(captured.waitingForLayoutBudget, false);
      expect(captured.partsPrepared, 1);
      expect(cache.layoutBuildCount, builds + 1);
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
      job.close();
      expect(job.isReady, false);
      expect(() => job.take(), throwsStateError);
      cache.clearUnpinned();
      expect(cache.estimatedRetainedBytes, 0);
    },
  );
  for (final backgroundPhase in [false, true]) {
    for (final warm in [false, true]) {
      test(
        'owner retirement during font capture cannot publish a late lease, background=$backgroundPhase,warm=$warm',
        () {
          final input = _input(_column);
          final cache = ForumBodyParagraphCache(
            maxEntries: 4,
            maxEstimatedBytes: 1 << 20,
          );
          addTearDown(cache.close);
          late ForumBodyInlinePlanPreparation job;
          var retire = false;
          final scaler = _RetiringScaler(() {
            if (retire) job.close();
          });
          if (warm) {
            cache
                .acquire(
                  content: backgroundPhase
                      ? input.atoms.single.background!.fontStrut
                      : input.atoms.single.rootBox!.fontStrut,
                  width: 300,
                  textScaler: scaler,
                )
                .release();
          }
          job = ForumBodyInlinePlanPreparation(
            input: input,
            cache: cache,
            textScaler: scaler,
            ensureOwner: () {},
          );
          addTearDown(job.close);
          if (backgroundPhase) {
            expect(job.advance(maxParts: 1).partsPrepared, 1);
            expect(cache.activeLeases, 0);
          }
          retire = true;
          expect(() => job.advance(maxParts: 1), throwsStateError);
          expect(job.isReady, false);
          expect(() => job.take(), throwsStateError);
          expect(cache.activeLeases, 0);
          expect(cache.pictureBuildCount, 0);
          cache.clearUnpinned();
          expect(cache.estimatedRetainedBytes, 0);
        },
      );
    }
  }
  test(
    'root font keeps effective native leading without a background or source request',
    () {
      final input = _input(_column, background: 'transparent');
      final root = input.atoms.single.rootBox!;
      expect(input.atoms.single.background, isNull);
      expect(root.fontStrut.isSourceFree, true);
      expect(root.fontStrut.projection.text, isEmpty);
      expect(root.fontStrut.style.textStyle.height, 3);
      expect(root.fontStrut.style.textStyle.fontSize, 40);
      expect(
        input.content.contexts.any((c) => identical(c.content, root.fontStrut)),
        false,
      );
      expect(
        input.atoms.single.nativeRequests.any(
          (r) => identical(r.content, root.fontStrut),
        ),
        false,
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final lease = cache.acquire(
        content: root.fontStrut,
        width: 300,
        textScaler: const TextScaler.linear(1.5),
      );
      final native = TextPainter(
        text: TextSpan(text: '', style: root.fontStrut.style.textStyle),
        textDirection: root.fontStrut.style.textDirection,
        textScaler: const TextScaler.linear(1.5),
      )..layout();
      try {
        expect(lease.layout.height, native.height);
        expect(
          lease.layout.alphabeticBaseline,
          native.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        );
        expect(lease.layout.height, 180);
        expect(lease.layout.lines, isEmpty);
      } finally {
        lease.release();
        native.dispose();
      }
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'actual columns, spanning segments and soft spaces retain the same pure root paint input',
    () {
      final kinds = <Type>{};
      for (final html in [_column, _segment, _space]) {
        final input = _input(html);
        expect(input.atoms, isNotEmpty);
        for (final atom in input.atoms) {
          kinds.add(atom.runtimeType);
          final background = _background(atom)!;
          expect(background.color, const Color(0x80ff0000));
          expect(background.rootPath, '0');
          final font = background.fontStrut;
          expect(font.isSourceFree, true);
          expect(font.projection.text, isEmpty);
          expect(font.style.textStyle.fontSize, 40);
          expect(font.style.textStyle.height, kTextHeightNone);
          expect(
            atom.nativeRequests.any((r) => identical(r.content, font)),
            false,
          );
          expect(
            input.content.contexts.any((c) => identical(c.content, font)),
            false,
          );
          expect(_background(atom.mapRequests((r) => r)), same(background));
          expect(atom.mapRequests((r) => r).rootBox, same(atom.rootBox));
          expect(atom.rootBox!.fontStrut.style.textStyle.height, 3);
        }
        final bands = <ForumBodyTextBandContent>{
          for (final atom in input.atoms)
            for (final request in atom.nativeRequests)
              if (request is ForumBodyTextBandChildRequest) request.band,
        };
        final originals = input.atoms.map(_background).toList();
        final roots = input.atoms.map((a) => a.rootBox).toList();
        for (final band in bands) {
          input.replaceBand(band, 1);
          expect(input.atoms.map(_background), orderedEquals(originals));
          expect(input.atoms.map((a) => a.rootBox), orderedEquals(roots));
          input.replaceBand(band, null);
          expect(input.atoms.map(_background), orderedEquals(originals));
          expect(input.atoms.map((a) => a.rootBox), orderedEquals(roots));
        }
      }
      expect(
        kinds,
        containsAll([
          ForumBodyRubyColumnAtomRequest,
          ForumBodyRubySegmentAtomRequest,
          ForumBodyRubySoftSpaceAtomRequest,
        ]),
      );
    },
  );
  test(
    'natural source-free container font uses actual scaling, independently of base size and author line-height',
    () {
      final input = _input(_column);
      final request =
          (input.atoms.single as ForumBodyRubyColumnAtomRequest).value;
      final background = request.background!;
      expect(request.base.content.style.textStyle.fontSize, 20);
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      final lease = cache.acquire(
        content: background.fontStrut,
        width: 300,
        textScaler: const TextScaler.linear(1.5),
      );
      final native = TextPainter(
        text: TextSpan(text: '', style: background.fontStrut.style.textStyle),
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(1.5),
      )..layout();
      try {
        expect(lease.layout.height, native.height);
        expect(
          lease.layout.alphabeticBaseline,
          native.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        );
        expect(lease.layout.height, 60);
        expect(lease.layout.lines, isEmpty);
      } finally {
        native.dispose();
        lease.release();
        cache.close();
      }
    },
  );
  test(
    'transparent or overridden root backgrounds do not allocate a font descriptor',
    () {
      for (final scope in [
        ForumBodyStyleScope.forceBody,
        ForumBodyStyleScope.forceAll,
      ]) {
        expect(
          _input(_column, scope: scope).atoms.map(_background),
          everyElement(isNull),
        );
      }
      expect(
        _input(_column, background: 'transparent').atoms.map(_background),
        everyElement(isNull),
      );
      expect(
        _input(_column, background: 'none').atoms.map(_background),
        everyElement(isNull),
      );
    },
  );
  test('requests reject a font descriptor from another text/style scope', () {
    final input = _input(_column);
    final original =
        (input.atoms.single as ForumBodyRubyColumnAtomRequest).value;
    final other =
        (_input('<rb>B</rb><rt>y</rt>').atoms.single
                as ForumBodyRubyColumnAtomRequest)
            .value;
    expect(
      () => ForumBodyRubyColumnRequest.layers(
        base: other.base,
        annotations: other.annotations,
        rootBox: original.rootBox,
      ),
      throwsArgumentError,
    );
    expect(
      () => ForumBodyRubyColumnRequest.layers(
        base: original.base,
        annotations: original.annotations,
        background: original.background,
        rootBox: ForumBodyRubyRootBoxInput(
          rootPath: 'foreign-root',
          fontStrut: original.rootBox!.fontStrut,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => ForumBodyRubyColumnRequest.layers(
        base: other.base,
        annotations: other.annotations,
        background: original.background,
      ),
      throwsArgumentError,
    );
    expect(
      () => ForumBodyRubySegmentRequest(
        bases: [other.base],
        sides: [ForumBodyRubySide.over],
        spans: [
          (
            request: other.annotation,
            startColumn: 0,
            endColumn: 1,
            annotationIndex: 0,
            gap: 0.0,
          ),
        ],
        background: original.background,
      ),
      throwsArgumentError,
    );
    final gap = _input(
      _space,
    ).atoms.whereType<ForumBodyRubySoftSpaceAtomRequest>().single.value;
    expect(
      () => ForumBodyRubySoftSpaceRequest(
        beforeColumn: gap.beforeColumn,
        members: gap.members,
        sides: gap.sides,
        background: original.background,
      ),
      throwsArgumentError,
    );
  });
  test(
    'color input preserves float precision and rejects nonfinite or source-bearing font boxes',
    () {
      final original =
          (_input(_column).atoms.single as ForumBodyRubyColumnAtomRequest)
              .value;
      ForumBodyRubyContainerBackground create(Color color) =>
          ForumBodyRubyContainerBackground(
            rootPath: '0',
            fontStrut: original.background!.fontStrut,
            color: color,
          );
      const one = Color.from(alpha: .5001, red: .2, green: .3, blue: .4);
      const two = Color.from(alpha: .5002, red: .2, green: .3, blue: .4);
      expect(one.toARGB32(), two.toARGB32());
      expect(create(one).color, one);
      expect(create(two).color, two);
      expect(create(one).color, isNot(create(two).color));
      expect(
        () => create(
          const Color.from(alpha: double.nan, red: 0, green: 0, blue: 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyRubyContainerBackground(
          rootPath: '0',
          fontStrut: original.base.content,
          color: one,
        ),
        throwsArgumentError,
      );
    },
  );
}

final class _RetiringScaler extends TextScaler {
  const _RetiringScaler(this.onScale);
  final void Function() onScale;
  @override
  double scale(double fontSize) {
    onScale();
    return fontSize;
  }

  @override
  double get textScaleFactor => 1;
}
