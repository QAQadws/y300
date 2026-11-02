import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 25 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyParagraphContent _content({
  TextDirection direction = TextDirection.ltr,
  String? html,
}) {
  final doc = const ForumBodyParser().parse(
    html:
        html ??
        '<p style="white-space:pre-wrap;line-height:.4">'
            '<span style="background-color:rgba(0,255,0,.4);text-decoration:underline">'
            'A e<span style="font-size:31px">́</span> ؀<span style="font-size:31px">A</span>'
            ' 👩‍👩‍👧‍👦 Z</span>\n</p>',
    sourceId: 'physical-line',
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
          shadows: [
            Shadow(
              color: Color(0xffaa0000),
              offset: Offset(2, -3),
              blurRadius: 2,
            ),
          ],
        ),
        fontRevision: 'physical-line-ahem',
        linkColor: const Color(0xff0000ff),
        textDirection: direction,
      ),
    ),
  );
}

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 8,
    maxEstimatedBytes: 1 << 24,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyParagraphLineFrames _frames(ForumBodyParagraphLease parent) {
  final job = ForumBodyParagraphLineFramePreparation(
    parent: parent,
    ensureOwner: () {},
  );
  addTearDown(job.close);
  while (!job.isReady) {
    expect(job.advance(maxParts: 1), 1);
  }
  return job.takeFrames();
}

ForumBodyParagraphRowView _group(ForumBodyParagraphLease parent, int start) {
  final job = ForumBodyParagraphRowPreparation(
    parent: parent,
    startLine: start,
    ensureOwner: () {},
  );
  addTearDown(job.close);
  while (!job.isReady) {
    expect(job.advance(maxParts: 1), 1);
  }
  return ForumBodyParagraphRowView.bind(
    parent: parent,
    metrics: job.takeMetrics(),
    ensureOwner: () {},
  );
}

List<ForumBodyParagraphPhysicalLineSelector> _finish(
  ForumBodyParagraphPhysicalLinePreparation job,
) {
  addTearDown(job.close);
  for (var i = 0; !job.isReady && i < 10000; i++) {
    expect(job.advance(maxParts: 1), 1);
  }
  expect(job.isReady, isTrue);
  expect(job.advance(maxParts: 8), 0);
  return job.takeSelectors();
}

ForumBodyTextPictureLease _scene(ForumBodyTextPicturePreparation job) {
  addTearDown(job.close);
  while (!job.isReady) {
    final step = job.advance(maxParts: 1);
    expect(step.partsPrepared, lessThanOrEqualTo(1));
    expect(step.picturesRecorded, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
  }
  return job.takeLease();
}

class _Images {
  final _pictures = <ui.Picture>[];
  Future<List<int>> pixels(
    void Function(Canvas) draw,
    int height,
    int dpr,
  ) async {
    final rec = ui.PictureRecorder();
    draw(Canvas(rec)..scale(dpr.toDouble()));
    final pic = rec.endRecording();
    // Keep comparison inputs alive until the comparison ends. Disposing the
    // reference between captures can itself change native fallback shadows.
    _pictures.add(pic);
    final image = await pic.toImage(180 * dpr, height * dpr);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList(growable: false);
    } finally {
      image.dispose();
    }
  }

  void close() {
    for (final p in _pictures) {
      p.dispose();
    }
    _pictures.clear();
  }
}

void _exact(List<int> actual, List<int> expected, String reason) {
  expect(actual.length, expected.length);
  var differences = 0, max = 0;
  for (var i = 0; i < actual.length; i++) {
    final d = (actual[i] - expected[i]).abs();
    if (d != 0) differences++;
    if (d > max) max = d;
  }
  expect(differences, 0, reason: '$reason; max=$max');
}

Matcher _failure(ForumBodyParagraphRowFailure failure) => throwsA(
  isA<ForumBodyParagraphRowException>().having(
    (e) => e.failure,
    'failure',
    failure,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Nonlinear()]) {
      for (final width in [1.0, 140.0]) {
        test(
          'physical conservation and scenes inside complete groups $direction/$scaler/$width',
          () async {
            final cache = _cache(), content = _content(direction: direction);
            final parent = cache.acquire(
              content: content,
              width: width,
              textScaler: scaler,
              rowIsolationPitch: 256,
            );
            final frames = _frames(parent), images = _Images();
            addTearDown(images.close);
            cache.prepareTextPaint(parent);
            var spanning = 0;
            final text = StringBuffer();
            for (var start = 0; start < parent.layout.lineCount;) {
              final group = _group(parent, start), metrics = group.metrics;
              text.write(group.projection.text);
              if (metrics.lineCount > 1) spanning++;
              final lines = _finish(
                ForumBodyParagraphPhysicalLinePreparation(
                  group: group,
                  frames: frames,
                  ensureOwner: () {},
                ),
              );
              expect(lines.length, metrics.lineCount);
              expect(() => lines.clear(), throwsUnsupportedError);
              expect(cache.layoutBuildCount, 1);
              expect(cache.activeLeases, 1);
              for (var j = 0; j < lines.length; j++) {
                expect(lines[j].lineIndex, start + j);
                expect(
                  lines[j].matchesInput(
                    nativeInputIdentity: parent.nativeInputIdentity,
                    group: group.selector,
                  ),
                  isTrue,
                );
                if (j > 0) {
                  expect(
                    lines[j].selector.clipTop,
                    lines[j - 1].selector.clipBottom,
                  );
                }
              }
              final offsets = [
                for (final line in lines)
                  Offset(
                    35,
                    40 + line.selector.originY - group.selector.originY,
                  ),
              ];
              final scene = _scene(
                ForumBodyTextPicturePreparation(
                  cache: cache,
                  input: ForumBodyTextPictureInput(
                    commands: [
                      for (var j = 0; j < lines.length; j++)
                        ForumBodyTextPictureCommand.fromPhysicalLine(
                          group,
                          lines[j],
                          offsets[j],
                        ),
                    ],
                  ),
                  text: const [],
                  paragraphRows: [group],
                  ensureOwner: () {},
                ),
              );
              for (final dpr in [1, 3]) {
                final h = group.height.ceil() + 80;
                final expected = await images.pixels(
                  (c) => group.paint(c, const Offset(35, 40)),
                  h,
                  dpr,
                );
                final actual = await images.pixels(
                  (c) {
                    for (var j = 0; j < lines.length; j++) {
                      group.paintPhysicalLine(c, offsets[j], lines[j]);
                    }
                  },
                  h,
                  dpr,
                );
                final prepared = await images.pixels(
                  (c) => scene.paint(c, Offset.zero),
                  h,
                  dpr,
                );
                _exact(actual, expected, 'direct group $start DPR$dpr');
                _exact(prepared, expected, 'prepared group $start DPR$dpr');
              }
              scene.release();
              cache.clearUnpinned();
              expect(cache.entryCount, 1);
              start = metrics.selector.endLine;
            }
            expect(text.toString(), content.projection.text);
            if (width == 1) expect(spanning, greaterThan(0));
            expect(cache.layoutBuildCount, 1);
            parent.release();
            cache.clearUnpinned();
            expect(cache.entryCount, 0);
          },
        );
      }
    }
  }

  test('internal grapheme rows need their own measured isolation gap', () {
    final cache = _cache(), content = _content(html: '<p>👩‍👩‍👧‍👦</p>');
    final parent = cache.acquire(
      content: content,
      width: 1,
      rowIsolationPitch: 40,
    );
    final group = _group(parent, 0), frames = _frames(parent);
    expect(group.metrics.lineCount, greaterThan(1));
    expect(
      () => _group(parent, 1),
      _failure(ForumBodyParagraphRowFailure.source),
    );
    final job = ForumBodyParagraphPhysicalLinePreparation(
      group: group,
      frames: frames,
      ensureOwner: () {},
    );
    double? needed;
    try {
      _finish(job);
    } on ForumBodyParagraphRowException catch (e) {
      expect(e.failure, ForumBodyParagraphRowFailure.isolation);
      needed = e.requiredPitch;
    }
    expect(needed, greaterThan(40));
    final retried = cache.acquire(
      content: content,
      width: 1,
      rowIsolationPitch: needed,
    );
    final lines = _finish(
      ForumBodyParagraphPhysicalLinePreparation(
        group: _group(retried, 0),
        frames: _frames(retried),
        ensureOwner: () {},
      ),
    );
    expect(lines.length, retried.layout.lineCount);
    parent.release();
    retried.release();
  });

  test(
    'frame/source budgets and ready retirement do not release borrowed groups',
    () {
      final cache = _cache(), content = _content(html: '<p>👩‍👩‍👧‍👦</p>');
      final parent = cache.acquire(
        content: content,
        width: 1,
        rowIsolationPitch: 256,
      );
      final group = _group(parent, 0), frames = _frames(parent);
      expect(
        () => ForumBodyParagraphPhysicalLinePreparation(
          group: group,
          frames: frames,
          ensureOwner: () {},
          maxLines: 1,
        ),
        _failure(ForumBodyParagraphRowFailure.limit),
      );
      final boxes = ForumBodyParagraphPhysicalLinePreparation(
        group: group,
        frames: frames,
        ensureOwner: () {},
        maxBoxes: 0,
      );
      expect(
        () => _finish(boxes),
        _failure(ForumBodyParagraphRowFailure.limit),
      );
      final foreign = cache.acquire(
        content: content,
        width: 2,
        rowIsolationPitch: 256,
      );
      expect(
        () => ForumBodyParagraphPhysicalLinePreparation(
          group: group,
          frames: _frames(foreign),
          ensureOwner: () {},
        ),
        _failure(ForumBodyParagraphRowFailure.source),
      );
      final early = ForumBodyParagraphPhysicalLinePreparation(
        group: group,
        frames: frames,
        ensureOwner: () {},
      );
      expect(early.takeSelectors, throwsStateError);
      var active = true;
      final job = ForumBodyParagraphPhysicalLinePreparation(
        group: group,
        frames: frames,
        ensureOwner: () {
          if (!active) throw StateError('generation');
        },
      );
      while (!job.isReady) {
        job.advance(maxParts: 1);
      }
      active = false;
      expect(job.takeSelectors, throwsStateError);
      expect(job.isReady, isFalse);
      expect(parent.isActive, isTrue);
      expect(cache.activeLeases, 2);
      foreign.release();
      parent.release();
    },
  );

  for (final retirement in ['parent', 'cache', 'close', 'reentry']) {
    test('ready physical selectors reject $retirement retirement', () {
      final cache = _cache();
      final parent = cache.acquire(
        content: _content(),
        width: 140,
        rowIsolationPitch: 256,
      );
      final group = _group(parent, 0), frames = _frames(parent);
      void Function()? callback;
      final job = ForumBodyParagraphPhysicalLinePreparation(
        group: group,
        frames: frames,
        ensureOwner: () => callback?.call(),
      );
      while (!job.isReady) {
        job.advance(maxParts: 1);
      }
      switch (retirement) {
        case 'parent':
          parent.release();
        case 'cache':
          cache.close();
        case 'close':
          callback = job.close;
        case 'reentry':
          callback = () => job.advance(maxParts: 1);
      }
      expect(job.takeSelectors, throwsStateError);
      expect(job.isReady, isFalse);
      expect(() => job.advance(maxParts: 1), throwsStateError);
    });
  }

  test(
    'physical selectors bind to complete groups and scene dependencies',
    () async {
      final cache = _cache(), images = _Images();
      addTearDown(images.close);
      final content = _content(html: '<p>👩‍👩‍👧‍👦</p>');
      final parent = cache.acquire(
        content: content,
        width: 1,
        rowIsolationPitch: 256,
      );
      final group = _group(parent, 0), frames = _frames(parent);
      final lines = _finish(
        ForumBodyParagraphPhysicalLinePreparation(
          group: group,
          frames: frames,
          ensureOwner: () {},
        ),
      );
      expect(lines.length, greaterThan(1));
      final rec = ui.PictureRecorder();
      expect(
        () => group.paintPhysicalLine(Canvas(rec), Offset.zero, lines.first),
        throwsStateError,
      );
      rec.endRecording().dispose();
      cache.prepareTextPaint(parent);
      final expected = await images.pixels(
        (c) => group.paint(c, const Offset(35, 40)),
        group.height.ceil() + 80,
        3,
      );
      final offsets = [
        for (final line in lines)
          Offset(35, 40 + line.selector.originY - group.selector.originY),
      ];
      final commands = [
        for (var j = 0; j < lines.length; j++)
          ForumBodyTextPictureCommand.fromPhysicalLine(
            group,
            lines[j],
            offsets[j],
          ),
      ];
      final normal = ForumBodyTextPictureInput(
        commands: [
          for (var j = 0; j < lines.length; j++)
            ForumBodyTextPictureCommand.fromParagraphRow(group, offsets[j]),
        ],
      );
      final input = ForumBodyTextPictureInput(commands: commands);
      expect(input, isNot(normal));
      expect(
        input.estimatedInputBytes - normal.estimatedInputBytes,
        128 * lines.length,
      );
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand(
              nativeInputIdentity: parent.nativeInputIdentity,
              offset: Offset.zero,
              physicalLine: lines.first,
            ),
          ],
        ),
        throwsArgumentError,
      );
      final foreign = cache.acquire(
        content: content,
        width: 2,
        rowIsolationPitch: 256,
      );
      final foreignGroup = _group(foreign, 0);
      expect(
        () => ForumBodyTextPictureCommand.fromPhysicalLine(
          foreignGroup,
          lines.first,
          Offset.zero,
        ),
        throwsArgumentError,
      );
      final other = ui.PictureRecorder();
      expect(
        () => foreignGroup.paintPhysicalLine(
          Canvas(other),
          Offset.zero,
          lines.first,
        ),
        _failure(ForumBodyParagraphRowFailure.source),
      );
      other.endRecording().dispose();
      foreign.release();
      final job = ForumBodyTextPicturePreparation(
        cache: cache,
        input: input,
        text: const [],
        paragraphRows: [group],
        ensureOwner: () {},
      );
      expect(
        cache.activeLeases,
        2,
        reason: 'one private alias for all physical strips',
      );
      final native = parent.layout;
      parent.release();
      final scene = _scene(job);
      cache.clearUnpinned();
      expect(native.isDisposed, isTrue);
      expect(cache.activeLeases, 1);
      final actual = await images.pixels(
        (c) => scene.paint(c, Offset.zero),
        group.height.ceil() + 80,
        3,
      );
      _exact(
        actual,
        expected,
        'scene independent of released source/native lease',
      );
      scene.release();
      cache.clearUnpinned();
      expect(cache.entryCount, 0);
      expect(cache.layoutBuildCount, 2);
    },
  );
}
