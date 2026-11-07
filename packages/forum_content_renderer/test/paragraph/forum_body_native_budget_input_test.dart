import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyParagraphCache _cache({int entries = 16, int bytes = 1 << 24}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: bytes,
  );
  addTearDown(cache.close);
  return cache;
}

({
  ForumBodyParagraphContent content,
  ForumBodyTextPictureInput pictureInput,
  List<ForumBodyNativeRequestSlot> nativeFootprint,
  List<ForumBodyNativeBudgetSlot> nativeBudgetFootprint,
})
_measure(ForumBodyParagraphCache cache, {String body = 'ABC'}) {
  final document = const ForumBodyParser().parse(
    html: '<p>$body</p>',
    sourceId: 'mixed-budget',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'budget-ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  final content = const ForumBodyParagraphContentBuilder().build(
    document: document,
    path: '0',
    styles: styles,
  );
  final label = ForumBodyDecorationTextInput.label(
    text: '1.',
    style: content.style,
    fontRevision: content.fontRevision,
    styleRevision: content.styleRevision,
  );
  final textLease = cache.acquire(content: content, width: 80);
  final labelLease = cache.acquireDecorationText(input: label);
  try {
    final picture = ForumBodyTextPictureInput(
      commands: [
        ForumBodyTextPictureCommand.fromText(textLease, Offset.zero),
        ForumBodyTextPictureCommand.fromDecorationText(
          labelLease,
          const Offset(0, 20),
        ),
      ],
    );
    final fonts = <ForumBodyNativeRequestSlot>[
      (
        request: ForumBodyTextRequest.paragraph(content),
        width: 80,
        minimumLineCount: 1,
      ),
      (
        request: ForumBodyDecorationTextRequest(label),
        width: 80,
        minimumLineCount: 1,
      ),
    ];
    return (
      content: content,
      pictureInput: picture,
      nativeFootprint: fonts,
      nativeBudgetFootprint: [
        ...fonts,
        (
          request: ForumBodyTextPictureBudgetInput(picture),
          width: 80,
          minimumLineCount: 0,
        ),
      ],
    );
  } finally {
    labelLease.release();
    textLease.release();
  }
}

void _include(
  ForumBodyParagraphBudgetProbe probe,
  ForumBodyNativeBudgetSlot slot,
) => slot.request.includeBudget(
  probe,
  width: slot.width,
  textScaler: TextScaler.noScaling,
  minimumLineCount: slot.minimumLineCount,
);

Map<Object, int> _costs(ForumBodyParagraphBudgetProbe probe) => {
  for (final item in probe.snapshotNativeEstimates())
    item.identity: item.estimatedBytes,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final body in [
    'ABC',
    '<span style="font-size:31px">A</span><b>B</b>C',
  ]) {
    test(
      'mixed real font/scene keys deduplicate without native work: $body',
      () {
        final cache = _cache(), metrics = _measure(cache, body: body);
        cache.clearUnpinned();
        final before = (
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
            ),
            probe = cache.createBudgetProbe(captureInputEstimates: true),
            reference = cache.createBudgetProbe(captureInputEstimates: true);
        addTearDown(probe.close);
        addTearDown(reference.close);
        final inputs = metrics.nativeBudgetFootprint.toList();
        expect(inputs.length, greaterThan(2));
        expect(inputs.last.request, isA<ForumBodyTextPictureBudgetInput>());
        expect(inputs.last.request, isNot(isA<ForumBodyNativeRequest>()));
        for (final slot in inputs) {
          _include(probe, slot);
        }
        for (final slot in metrics.nativeFootprint) {
          _include(reference, slot);
        }
        reference.includeTextPicture(metrics.pictureInput);
        expect(_costs(probe), _costs(reference));
        final first = _costs(probe);
        for (final slot in inputs) {
          _include(probe, slot);
        }
        expect(_costs(probe), first);
        expect((
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.hitCount,
        ), before);
        expect(cache.activeLeases, 0);
        expect(cache.entryCount, 0);
      },
    );
  }

  test(
    'picture input uses frozen geometry without invoking caller scaling',
    () {
      final cache = _cache(), metrics = _measure(cache);
      cache.clearUnpinned();
      final probe = cache.createBudgetProbe(captureInputEstimates: true);
      addTearDown(probe.close);
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final spec = ForumBodyTextPictureBudgetInput(metrics.pictureInput);
      spec.includeBudget(
        probe,
        width: 1,
        textScaler: const _FailScaler(),
        minimumLineCount: 0,
      );
      expect(
        probe.snapshotNativeEstimates().single.estimatedBytes,
        metrics.pictureInput.estimatedBytes,
      );
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'the final scene slot can exceed intrinsic entry capacity before acquisition',
    () {
      final cache = _cache(entries: 2), metrics = _measure(cache);
      cache.clearUnpinned();
      final probe = cache.createBudgetProbe();
      addTearDown(probe.close);
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final inputs = metrics.nativeBudgetFootprint.toList();
      expect(inputs, hasLength(3));
      _include(probe, inputs[0]);
      _include(probe, inputs[1]);
      expect(
        () => _include(probe, inputs.last),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      expect(cache.activeLeases, 0);
    },
  );

  test('picture byte admission is exact even without font acquisition', () {
    final measured = _cache(),
        metrics = _measure(measured),
        cache = _cache(
          entries: 1,
          bytes: metrics.pictureInput.estimatedBytes - 1,
        );
    final probe = cache.createBudgetProbe();
    addTearDown(probe.close);
    expect(
      () => _include(probe, metrics.nativeBudgetFootprint.last),
      throwsA(
        isA<ForumBodyParagraphBudgetException>().having(
          (e) => e.requiredEstimatedBytes,
          'required bytes',
          metrics.pictureInput.estimatedBytes,
        ),
      ),
    );
    expect(cache.layoutBuildCount, 0);
    expect(cache.pictureBuildCount, 0);
    expect(cache.activeLeases, 0);
  });

  test('accepted pure budgets do not make a cold source or scene readable', () {
    final cache = _cache(), metrics = _measure(cache);
    cache.clearUnpinned();
    final probe = cache.createBudgetProbe();
    addTearDown(probe.close);
    for (final slot in metrics.nativeBudgetFootprint) {
      _include(probe, slot);
    }
    final before = (cache.layoutBuildCount, cache.pictureBuildCount);
    expect(cache.tryAcquireCached(content: metrics.content, width: 80), isNull);
    expect(cache.tryAcquireTextPicture(metrics.pictureInput), isNull);
    expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
    expect(cache.activeLeases, 0);
    cache.close();
    expect(
      () => _include(probe, metrics.nativeBudgetFootprint.last),
      throwsStateError,
    );
  });
}

final class _FailScaler extends TextScaler {
  const _FailScaler();
  @override
  double scale(double fontSize) =>
      throw StateError('Frozen scene must not rescale');
  @override
  double get textScaleFactor => throw StateError('Use actual font samples');
}
