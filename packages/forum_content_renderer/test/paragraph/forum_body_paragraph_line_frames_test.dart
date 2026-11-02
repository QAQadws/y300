import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_native_space_span.dart';

class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 25 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyParagraphContent _content({
  TextDirection direction = TextDirection.ltr,
  String height = '.4',
  String? html,
  bool indent = false,
  ForumBodyParagraphLayoutMode mode = ForumBodyParagraphLayoutMode.wrap,
}) {
  final doc = const ForumBodyParser().parse(
    html:
        html ??
        '<p style="white-space:pre-wrap;line-height:$height">'
            'ffi 中 العربية 👩‍👩‍👧‍👦 e<span style="font-size:31px">́</span> '
            '؀<span style="font-size:31px">A B</span> \n\nEND\n</p>',
    sourceId: 'line-frames',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: doc,
    path: '0',
    layoutMode: mode,
    styles: const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: Color(0xff123456),
        ),
        fontRevision: 'line-frames-ahem',
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

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 12,
    maxEstimatedBytes: 1 << 24,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyParagraphLineFrames _finish(
  ForumBodyParagraphLineFramePreparation job,
) {
  addTearDown(job.close);
  while (!job.isReady) {
    expect(job.advance(maxParts: 1), 1);
  }
  expect(job.advance(maxParts: 4), 0);
  return job.takeFrames();
}

TextPainter _oracle(ForumBodyParagraphLease parent, TextScaler scaler) {
  final content = parent.content, layout = parent.layout;
  final prefix = layout.firstLineIndent.requestedAdvance > 0;
  final body = content.textSpan;
  final painter =
      TextPainter(
        text: prefix
            ? TextSpan(
                style: body.style,
                children: [
                  ForumBodyNativeSpaceSpan.nonBreaking(
                    layout.firstLineIndent.appliedAdvance,
                  ),
                  ...body.children!,
                ],
              )
            : body,
        textDirection: content.style.textDirection,
        textAlign: content.style.textAlign,
        textScaler: scaler,
        locale: content.style.textStyle.locale,
        strutStyle: layout.rowIsolationPitch == null
            ? null
            : StrutStyle.fromTextStyle(
                content.style.textStyle,
                height:
                    layout.rowIsolationPitch! /
                    scaler.scale(content.style.textStyle.fontSize!),
                leading: 0,
                forceStrutHeight: true,
              ),
      )..layout(
        minWidth: layout.width - 2 * layout.horizontalInset,
        maxWidth: layout.width - 2 * layout.horizontalInset,
      );
  addTearDown(painter.dispose);
  return painter;
}

void _compare(ForumBodyParagraphLease parent, TextScaler scaler) {
  final oracle = _oracle(parent, scaler);
  final expected = [
    for (final box in oracle.getBoxesForSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: oracle.text!.toPlainText().length,
      ),
      boxHeightStyle: ui.BoxHeightStyle.max,
    ))
      (top: box.top, bottom: box.bottom),
  ];
  expect(parent.layout.queryMaximumLineFrames(), expected);
  final job = ForumBodyParagraphLineFramePreparation(
    parent: parent,
    ensureOwner: () {},
  );
  final result = _finish(job), unique = expected.toSet().toList();
  expect(result.content, same(parent.content));
  expect(result.nativeInputIdentity, parent.nativeInputIdentity);
  expect(result.lines, same(parent.layout.lines));
  expect(result.width, parent.layout.width);
  expect(result.height, oracle.height);
  expect(
    result.alphabeticBaseline,
    oracle.computeLineMetrics().isEmpty
        ? oracle.computeDistanceToActualBaseline(TextBaseline.alphabetic)
        : oracle.computeLineMetrics().first.baseline,
  );
  expect(
    result.nativeAlphabeticBaseline,
    oracle.computeDistanceToActualBaseline(TextBaseline.alphabetic),
  );
  expect(result.frames.length, parent.layout.lineCount);
  var end = 0.0;
  for (var i = 0; i < result.frames.length; i++) {
    final frame = result.frames[i];
    expect(frame.maximum, i < unique.length ? unique[i] : null);
    expect(frame.flowTop, end);
    expect(
      frame.flowBottom,
      i < unique.length ? unique[i].bottom : oracle.height,
    );
    end = frame.flowBottom;
  }
  if (result.frames.isNotEmpty) expect(end, oracle.height);
  expect(
    result.frames.where((f) => f.maximum == null).length,
    parent.layout.hasTerminalEmptyLine ? 1 : 0,
  );
  expect(() => result.frames.clear(), throwsUnsupportedError);
  expect(() => result.lines.clear(), throwsUnsupportedError);
  expect(() => job.advance(maxParts: 1), throwsStateError);
  parent.release();
  expect(result.frames.length, result.lines.length);
}

Matcher _failure(ForumBodyParagraphLineFrameFailure failure) => throwsA(
  isA<ForumBodyParagraphLineFrameException>().having(
    (e) => e.failure,
    'failure',
    failure,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Nonlinear()]) {
      for (final width in [1.0, 140.0]) {
        for (final pitch in [null, 256.0]) {
          for (final height in ['.4', '1.6']) {
            test(
              'actual native maximum frames $direction/$scaler/$width/$pitch/$height',
              () {
                final cache = _cache(),
                    content = _content(direction: direction, height: height);
                final parent = cache.acquire(
                  content: content,
                  width: width,
                  textScaler: scaler,
                  rowIsolationPitch: pitch,
                );
                final before = (
                  cache.layoutBuildCount,
                  cache.pictureBuildCount,
                  cache.activeLeases,
                  cache.hitCount,
                );
                _compare(parent, scaler);
                expect((
                  cache.layoutBuildCount,
                  cache.pictureBuildCount,
                  cache.activeLeases + 1,
                  cache.hitCount,
                ), before);
                cache.clearUnpinned();
                expect(cache.entryCount, 0);
              },
            );
          }
        }
      }
    }
  }
  for (final html in [
    '<p></p>',
    '<p><br></p>',
    '<p><br><br></p>',
    '<p style="white-space:pre-wrap">\u200d</p>',
    '<p style="white-space:pre-wrap">\u200b\nA</p>',
    '<p style="white-space:pre-wrap">\u2060\n\u2060</p>',
  ]) {
    for (final pitch in [null, 256.0]) {
      test('empty/control actual row frames $html/$pitch', () {
        final parent = _cache().acquire(
          content: _content(html: html),
          width: 140,
          rowIsolationPitch: pitch,
        );
        _compare(parent, TextScaler.noScaling);
      });
    }
  }
  for (final direction in TextDirection.values) {
    for (final pitch in [null, 256.0]) {
      test('actual indent/tracking max frames $direction/$pitch', () {
        final parent = _cache().acquire(
          content: _content(
            direction: direction,
            indent: true,
            html: '<p style="letter-spacing:-2px">AB CD EF GH IJ KL MN OP</p>',
          ),
          width: 45,
          textScaler: const _Nonlinear(),
          rowIsolationPitch: pitch,
        );
        _compare(parent, const _Nonlinear());
      });
    }
  }

  test('measured strut flow endpoints are not tight metric heights', () {
    final cache = _cache(),
        parent = cache.acquire(
          content: _content(),
          width: 140,
          rowIsolationPitch: 256,
        );
    final snapshot = _finish(
      ForumBodyParagraphLineFramePreparation(
        parent: parent,
        ensureOwner: () {},
      ),
    );
    for (var i = 0; i < snapshot.frames.length; i++) {
      expect(snapshot.frames[i].flowBottom - snapshot.frames[i].flowTop, 256);
      expect(snapshot.lines[i].bottom - snapshot.lines[i].top, lessThan(64));
    }
    parent.release();
    cache.clearUnpinned();
    cache.close();
    expect(snapshot.frames.last.flowBottom, snapshot.height);
    expect(snapshot.lines.first.baseline.isFinite, isTrue);
  });

  test(
    'long full-source query yields bounded parts and immutable retired data',
    () {
      final text = List.filled(2048, 'A\n').join();
      final cache = _cache(),
          parent = cache.acquire(
            content: _content(
              html: '<p style="white-space:pre-wrap">$text</p>',
            ),
            width: 140,
            rowIsolationPitch: 256,
          );
      final queried = parent.layout.queryMaximumLineFrames();
      expect(() => queried.clear(), throwsUnsupportedError);
      final job = ForumBodyParagraphLineFramePreparation(
        parent: parent,
        ensureOwner: () {},
      );
      var advances = 0;
      while (!job.isReady) {
        expect(job.advance(maxParts: 17), inInclusiveRange(1, 17));
        advances++;
      }
      expect(advances, greaterThan(100));
      final snapshot = job.takeFrames();
      expect(snapshot.frames.length, 2049);
      expect(snapshot.frames.last.maximum, isNull);
      expect(snapshot.frames.last.flowBottom, 2049 * 256);
      expect(cache.layoutBuildCount, 1);
      expect(cache.pictureBuildCount, 0);
      parent.release();
      cache.clearUnpinned();
      cache.close();
      expect(snapshot.frames[1000].maximum, (top: 256000.0, bottom: 256256.0));
      expect(snapshot.frames.last.flowBottom, snapshot.height);
    },
  );

  test(
    'limits, early take and coincident frames do not publish guessed rows',
    () {
      final cache = _cache(),
          parent = cache.acquire(content: _content(), width: 140);
      expect(
        () => ForumBodyParagraphLineFramePreparation(
          parent: parent,
          ensureOwner: () {},
          maxLines: 1,
        ),
        _failure(ForumBodyParagraphLineFrameFailure.limit),
      );
      final boxes = ForumBodyParagraphLineFramePreparation(
        parent: parent,
        ensureOwner: () {},
        maxBoxes: 0,
      );
      expect(
        () => boxes.advance(maxParts: 1),
        _failure(ForumBodyParagraphLineFrameFailure.limit),
      );
      final early = ForumBodyParagraphLineFramePreparation(
        parent: parent,
        ensureOwner: () {},
      );
      expect(() => early.advance(maxParts: 0), throwsArgumentError);
      expect(early.takeFrames, throwsStateError);
      expect(parent.isActive, isTrue);
      final degenerate = cache.acquire(
        content: _content(
          html: '<p style="line-height:.001;white-space:pre-wrap">A\nB\nC</p>',
        ),
        width: 140,
      );
      expect(degenerate.layout.lineCount, 3);
      expect(degenerate.layout.queryMaximumLineFrames(), isNotEmpty);
      final job = ForumBodyParagraphLineFramePreparation(
        parent: degenerate,
        ensureOwner: () {},
      );
      expect(
        () => _finish(job),
        _failure(ForumBodyParagraphLineFrameFailure.geometry),
      );
      expect(degenerate.isActive, isTrue);
      parent.release();
      degenerate.release();
    },
  );

  for (final retirement in [
    'parent',
    'owner',
    'generation',
    'close',
    'reentry',
  ]) {
    test('ready retirement $retirement rejects late frame publication', () {
      final cache = _cache(),
          parent = cache.acquire(content: _content(), width: 140);
      var active = true;
      void Function()? callback;
      final job = ForumBodyParagraphLineFramePreparation(
        parent: parent,
        ensureOwner: () {
          if (!active) throw StateError('retired generation');
          callback?.call();
        },
      );
      while (!job.isReady) {
        job.advance(maxParts: 1);
      }
      switch (retirement) {
        case 'parent':
          parent.release();
        case 'owner':
          cache.close();
        case 'generation':
          active = false;
        case 'close':
          callback = job.close;
        case 'reentry':
          callback = () => job.advance(maxParts: 1);
      }
      expect(job.takeFrames, throwsStateError);
      expect(job.isReady, isFalse);
      expect(() => job.advance(maxParts: 1), throwsStateError);
    });
  }
  test(
    'close/cancellation retain caller leases and non-wrap source is rejected',
    () {
      final cache = _cache(),
          parent = cache.acquire(content: _content(), width: 140);
      var active = true;
      final job = ForumBodyParagraphLineFramePreparation(
        parent: parent,
        ensureOwner: () {
          if (!active) throw StateError('cancel');
        },
      );
      expect(job.advance(maxParts: 1), 1);
      active = false;
      expect(() => job.advance(maxParts: 10), throwsStateError);
      expect(parent.isActive, isTrue);
      expect(cache.activeLeases, 1);
      final fit = cache.acquire(
        content: _content(
          html: '<p>ABCD</p>',
          mode: ForumBodyParagraphLayoutMode.fitSingleLine,
        ),
        width: 140,
      );
      expect(
        () => ForumBodyParagraphLineFramePreparation(
          parent: fit,
          ensureOwner: () {},
        ),
        _failure(ForumBodyParagraphLineFrameFailure.source),
      );
      fit.release();
      parent.release();
      cache.clearUnpinned();
      expect(cache.entryCount, 0);
    },
  );
}
