import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyParagraphContent _content({
  String? html,
  TextDirection direction = TextDirection.ltr,
  String fontRevision = 'row-reference-ahem',
  bool indent = false,
}) {
  final doc = const ForumBodyParser().parse(
    html: html ?? '<p>AB CD EF GH IJ KL MN OP</p>',
    sourceId: 'row-reference',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: Color(0xff123456),
        ),
        linkColor: const Color(0xff0000ff),
        fontRevision: fontRevision,
        textDirection: direction,
        firstLineIndent: ForumBodyLength(
          indent ? 2 : 0,
          ForumBodyLengthUnit.em,
        ),
      ),
    ),
    path: '0',
  );
}

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 16,
    maxEstimatedBytes: 1 << 24,
  );
  addTearDown(cache.close);
  return cache;
}

({ForumBodyParagraphLease natural, ForumBodyParagraphLease isolated}) _pair(
  ForumBodyParagraphCache cache,
  ForumBodyParagraphContent content, {
  double width = 140,
  TextScaler scaler = TextScaler.noScaling,
}) => (
  natural: cache.acquire(content: content, width: width, textScaler: scaler),
  isolated: cache.acquire(
    content: content,
    width: width,
    textScaler: scaler,
    rowIsolationPitch: 256,
  ),
);

ForumBodyParagraphRowReferencePreparation _job(
  ({ForumBodyParagraphLease natural, ForumBodyParagraphLease isolated}) pair, {
  void Function()? ensureOwner,
}) => ForumBodyParagraphRowReferencePreparation(
  natural: pair.natural,
  isolated: pair.isolated,
  ensureOwner: ensureOwner ?? () {},
);

ForumBodyParagraphRowReference _finish(
  ForumBodyParagraphRowReferencePreparation job,
) {
  addTearDown(job.close);
  while (!job.isReady) {
    expect(job.advance(maxParts: 1), 1);
  }
  return job.takeReference();
}

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 25 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

Matcher _failure(ForumBodyParagraphRowReferenceFailure failure) => throwsA(
  isA<ForumBodyParagraphRowReferenceException>().having(
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
        for (final height in ['.4', '1.6', '2.4', '37px']) {
          test('actual natural rows $direction/$scaler/$width/$height', () {
            final content = _content(
              direction: direction,
              html:
                  '<p style="line-height:$height">ffi é 中 العربية '
                  '👩‍👩‍👧‍👦 <span style="font-size:31px">AB 中</span> '
                  'e<span style="font-size:31px">́</span> '
                  '؀<span style="font-size:31px">A</span> X  <br>END<br></p>',
            );
            final cache = _cache();
            final pair = _pair(cache, content, width: width, scaler: scaler);
            final natural = pair.natural.layout;
            final isolated = pair.isolated.layout;
            final before = (
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
              cache.activeLeases,
            );
            final job = _job(pair);
            for (var i = 0; i < natural.lineCount; i++) {
              expect(job.advance(maxParts: 1), 1);
              expect(
                job.isReady,
                isFalse,
                reason: 'Only a fully verified pair publishes',
              );
            }
            expect(job.advance(maxParts: 1), 1);
            expect(job.advance(maxParts: 8), 0);
            final reference = job.takeReference();
            expect(reference.content, same(content));
            expect(
              reference.naturalInputIdentity,
              pair.natural.nativeInputIdentity,
            );
            expect(
              reference.isolatedInputIdentity,
              pair.isolated.nativeInputIdentity,
            );
            expect(
              reference.naturalInputIdentity,
              isNot(reference.isolatedInputIdentity),
            );
            expect(reference.naturalLines, same(natural.lines));
            expect(reference.isolatedLines, same(isolated.lines));
            expect(reference.width, natural.width);
            expect(reference.naturalHeight, natural.height);
            expect(reference.isolatedHeight, isolated.height);
            expect(reference.naturalBaseline, natural.alphabeticBaseline);
            expect(reference.isolatedBaseline, isolated.alphabeticBaseline);
            expect(reference.rowIsolationPitch, 256);
            expect(reference.lineCount, greaterThan(2));
            expect(reference.naturalHeight, lessThan(reference.isolatedHeight));
            expect(
              reference.naturalLines[1].baseline -
                  reference.naturalLines[0].baseline,
              isNot(reference.rowIsolationPitch),
            );
            expect(reference.firstLineIndent, same(natural.firstLineIndent));
            expect((
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
              cache.activeLeases,
            ), before);
            expect(isolated.isPaintPrepared, isFalse);
            expect(() => job.advance(maxParts: 1), throwsStateError);
            pair.natural.release();
            pair.isolated.release();
            cache.clearUnpinned();
            cache.close();
            expect(natural.isDisposed, isTrue);
            expect(isolated.isDisposed, isTrue);
            expect(cache.activeLeases, 0);
            // Numeric data stays valid after both native resources are gone.
            expect(reference.naturalLines.last.baseline.isFinite, isTrue);
            expect(reference.isolatedLines.last.baseline.isFinite, isTrue);
            expect(
              () => reference.naturalLines.clear(),
              throwsUnsupportedError,
            );
            expect(
              () => reference.isolatedLines.clear(),
              throwsUnsupportedError,
            );
          });
        }
      }
    }
  }

  test(
    'natural frames equal independent native measurement, not strut pitch',
    () {
      final content = _content(
        html:
            '<p style="line-height:.4">AB CD <span style="font-size:51px">EF</span> GH IJ KL</p>',
      );
      final pair = _pair(_cache(), content, width: 95);
      final reference = _finish(_job(pair));
      final raw = TextPainter(
        text: content.textSpan,
        textDirection: content.style.textDirection,
        textAlign: content.style.textAlign,
      )..layout(minWidth: 95, maxWidth: 95);
      try {
        final actual = raw.computeLineMetrics();
        expect(reference.naturalHeight, raw.height);
        expect(reference.naturalLines.length, actual.length);
        for (var i = 0; i < actual.length; i++) {
          final row = reference.naturalLines[i], native = actual[i];
          expect(row.top, native.baseline - native.ascent);
          expect(row.bottom, native.baseline + native.descent);
          expect(row.baseline, native.baseline);
          expect(row.left, native.left);
          expect(row.width, native.width);
        }
        // Mixed authored sizes retain real variable baseline advances.
        expect(
          {
            for (var i = 1; i < actual.length; i++)
              actual[i].baseline - actual[i - 1].baseline,
          }.length,
          greaterThan(1),
        );
      } finally {
        raw.dispose();
        pair.natural.release();
        pair.isolated.release();
      }
    },
  );

  for (final html in ['<p></p>', '<p><br></p>', '<p>A<br><br>B<br></p>']) {
    test('empty and hard-break source $html', () {
      final pair = _pair(_cache(), _content(html: html));
      final reference = _finish(_job(pair));
      expect(reference.naturalLines, same(pair.natural.layout.lines));
      expect(reference.naturalBaseline, pair.natural.layout.alphabeticBaseline);
      expect(reference.lineCount, pair.isolated.layout.lineCount);
      pair.natural.release();
      pair.isolated.release();
    });
  }

  for (final direction in TextDirection.values) {
    for (final width in [45.0, 140.0]) {
      test('actual reader indent and negative tracking $direction/$width', () {
        final pair = _pair(
          _cache(),
          _content(
            direction: direction,
            indent: true,
            html: '<p style="letter-spacing:-2px">AB CD EF GH IJ KL MN OP</p>',
          ),
          width: width,
          scaler: const _Nonlinear(),
        );
        final reference = _finish(_job(pair));
        expect(reference.firstLineIndent.requestedAdvance, greaterThan(0));
        expect(
          reference.firstLineIndent.appliedAdvance,
          pair.isolated.layout.firstLineIndent.appliedAdvance,
        );
        expect(reference.firstLineIndent.isReduced, width == 45);
        expect(pair.natural.layout.horizontalInset, greaterThan(0));
        pair.natural.release();
        pair.isolated.release();
      });
    }
  }

  test(
    'same native input is insufficient for a clone source or foreign owner',
    () {
      final content = _content(), clone = _content();
      final cache = _cache(), foreign = _cache();
      final natural = cache.acquire(content: content, width: 140);
      final aliasedClone = cache.acquire(content: clone, width: 140);
      expect(aliasedClone.nativeInputIdentity, natural.nativeInputIdentity);
      expect(
        natural.hasSameSourceAndInputsExceptRowIsolation(aliasedClone),
        isFalse,
      );
      for (final isolated in [
        cache.acquire(content: clone, width: 140, rowIsolationPitch: 256),
        foreign.acquire(content: content, width: 140, rowIsolationPitch: 256),
        cache.acquire(content: content, width: 141, rowIsolationPitch: 256),
        cache.acquire(
          content: content,
          width: 140,
          textScaler: const _Nonlinear(),
          rowIsolationPitch: 256,
        ),
        cache.acquire(
          content: _content(fontRevision: 'changed'),
          width: 140,
          rowIsolationPitch: 256,
        ),
        natural,
      ]) {
        expect(
          () => ForumBodyParagraphRowReferencePreparation(
            natural: natural,
            isolated: isolated,
            ensureOwner: () {},
          ),
          _failure(ForumBodyParagraphRowReferenceFailure.source),
        );
        expect(natural.isActive, isTrue);
      }
      final valid = cache.acquire(
        content: content,
        width: 140,
        rowIsolationPitch: 256,
      );
      expect(natural.hasSameSourceAndInputsExceptRowIsolation(valid), isTrue);
      expect(valid.nativeInputIdentity, isNot(natural.nativeInputIdentity));
      expect(
        () => ForumBodyParagraphRowReferencePreparation(
          natural: valid,
          isolated: natural,
          ensureOwner: () {},
        ),
        _failure(ForumBodyParagraphRowReferenceFailure.source),
      );
      valid.release();
      expect(natural.hasSameSourceAndInputsExceptRowIsolation(valid), isFalse);
      cache.close();
      foreign.close();
    },
  );

  test('row limit and early take cannot publish a partial reference', () {
    final pair = _pair(_cache(), _content());
    expect(
      () => ForumBodyParagraphRowReferencePreparation(
        natural: pair.natural,
        isolated: pair.isolated,
        ensureOwner: () {},
        maxLines: 1,
      ),
      _failure(ForumBodyParagraphRowReferenceFailure.limit),
    );
    final job = _job(pair);
    expect(() => job.advance(maxParts: 0), throwsArgumentError);
    expect(job.takeReference, throwsStateError);
    expect(() => job.advance(maxParts: 1), throwsStateError);
    expect(pair.natural.isActive, isTrue);
    expect(pair.isolated.isActive, isTrue);
  });

  for (final retire in [
    'natural',
    'isolated',
    'owner',
    'callback',
    'close',
    'reentry',
  ]) {
    test('ready retirement $retire rejects late publication', () {
      final cache = _cache(), pair = _pair(cache, _content());
      var active = true;
      void Function()? callback;
      final job = _job(
        pair,
        ensureOwner: () {
          if (!active) throw StateError('retired generation');
          callback?.call();
        },
      );
      while (!job.isReady) {
        job.advance(maxParts: 1);
      }
      switch (retire) {
        case 'natural':
          pair.natural.release();
        case 'isolated':
          pair.isolated.release();
        case 'owner':
          cache.close();
        case 'callback':
          active = false;
        case 'close':
          callback = job.close;
        case 'reentry':
          callback = () => job.advance(maxParts: 1);
      }
      expect(job.takeReference, throwsStateError);
      expect(job.isReady, isFalse);
      expect(() => job.advance(maxParts: 1), throwsStateError);
      job.close();
    });
  }

  test('mid-row cancellation and close do not retire borrowed leases', () {
    final cache = _cache(), pair = _pair(cache, _content());
    var calls = 0;
    final job = _job(
      pair,
      ensureOwner: () {
        if (++calls == 4) throw StateError('generation changed');
      },
    );
    expect(() => job.advance(maxParts: 100), throwsStateError);
    expect(job.isReady, isFalse);
    expect(cache.activeLeases, 2);
    final next = _job(pair)..close();
    expect(() => next.advance(maxParts: 1), throwsStateError);
    expect(cache.activeLeases, 2);
    pair.natural.release();
    pair.isolated.release();
    cache.clearUnpinned();
    expect(cache.activeLeases, 0);
    expect(cache.entryCount, 0);
  });
}
