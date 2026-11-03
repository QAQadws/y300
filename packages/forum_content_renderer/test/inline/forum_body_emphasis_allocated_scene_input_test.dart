import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/emphasis_allocation_fixture.dart';

ForumBodyParagraphLineFrames _frames(ForumBodyParagraphLease parent) {
  final job = ForumBodyParagraphLineFramePreparation(
    parent: parent,
    ensureOwner: () {},
  );
  while (!job.isReady) {
    job.advance(maxParts: 1);
  }
  return job.takeFrames();
}

class _Context {
  _Context() {
    row = fixture.row(0);
    final job = fixture.prepare(row);
    while (!job.isReady) {
      job.advance(maxParts: 1);
    }
    allocation = job.takeAllocation();
    phases = [
      for (final content in [
        allocation.paintInput.background,
        allocation.paintInput.foreground,
        allocation.paintInput.decoration,
      ])
        fixture.cache.acquire(
          content: content,
          width: fixture.width,
          textScaler: fixture.scaler,
          rowIsolationPitch: fixture.reference.rowIsolationPitch,
        ),
    ];
    tables = phases.map(_frames).toList();
  }
  final fixture = EmphasisAllocationFixture(body: 'AB CD', width: 140);
  late final EmphasisAllocationRowFixture row;
  late final ForumBodyEmphasisRowAllocation allocation;
  late final List<ForumBodyParagraphLease> phases;
  late final List<ForumBodyParagraphLineFrames> tables;
  ForumBodyEmphasisAllocatedSceneInputPreparation job({
    void Function()? owner,
    List<ForumBodyEmphasisMeasuredPaintPhase>? inputs,
  }) => ForumBodyEmphasisAllocatedSceneInputPreparation(
    allocation: allocation,
    source: fixture.isolated,
    ensureOwner: owner ?? () {},
    phases:
        inputs ??
        [for (var i = 0; i < 3; i++) (parent: phases[i], frames: tables[i])],
  );
}

ForumBodyEmphasisAllocatedSceneInput _finish(
  ForumBodyEmphasisAllocatedSceneInputPreparation job,
) {
  addTearDown(job.close);
  for (var n = 0; !job.isReady && n < 20000; n++) {
    expect(job.advance(maxParts: 1), 1);
  }
  expect(job.isReady, isTrue);
  return job.takeInput();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  ForumBodyEmphasisAllocatedPreparation visibleJob(
    ForumBodyEmphasisAllocatedSceneInput input,
    ForumBodyParagraphCache cache, {
    Iterable<ForumBodyNativeParagraphLease> Function()? prefix,
  }) => ForumBodyEmphasisAllocatedPreparation(
    input: input.allocation.source.rowInput!,
    allocation: input.allocation,
    plannedSceneInput: input,
    cache: cache,
    ensureOwner: () {},
    width: 140,
    expectedTextScaler: TextScaler.noScaling,
    additionalOwnedLeases: prefix,
  );
  ForumBodyEmphasisAllocatedLayout finishVisible(
    ForumBodyEmphasisAllocatedPreparation job, {
    bool cachedOnly = false,
  }) {
    addTearDown(job.close);
    for (var n = 0; !job.isReady && n < 20000; n++) {
      final step = job.advance(maxParts: 1, cachedOnly: cachedOnly);
      expect(
        step.nativeLayoutsBuilt + step.picturesRecorded,
        lessThanOrEqualTo(1),
      );
      expect(step.waitingForLayoutBudget, isFalse);
      expect(job.cacheMiss, isFalse);
    }
    expect(job.isReady, isTrue);
    return job.takeLayout();
  }

  test(
    'planned scenes resume cold cached-only misses and share warm concurrent delivery',
    () {
      final c = _Context(), input = _finish(c.job());
      c.fixture.cache.close();
      final cache = ForumBodyParagraphCache(
        maxEntries: 6,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final job = visibleJob(input, cache);
      for (var n = 0; !job.cacheMiss && n < 20000; n++) {
        job.advance(maxParts: 1, cachedOnly: true);
      }
      expect(job.cacheMiss, isTrue);
      expect(cache.layoutBuildCount, 0);
      expect(cache.pictureBuildCount, 0);
      final first = finishVisible(job);
      addTearDown(first.close);
      expect(first.pictureInput, input.pictureInput);
      final counters = (cache.layoutBuildCount, cache.pictureBuildCount);
      final second = finishVisible(
        visibleJob(input, cache, prefix: () => first.nativeLeases),
        cachedOnly: true,
      );
      expect(second.pictureInput, input.pictureInput);
      expect((cache.layoutBuildCount, cache.pictureBuildCount), counters);
      expect(cache.activeLeases, 4);
      second.close();
      first.close();
      expect(cache.activeLeases, 0);
    },
  );
  for (final declared in [false, true]) {
    test('planned scene own peak versus external pin declared=$declared', () {
      final c = _Context(), input = _finish(c.job());
      c.fixture.cache.close();
      final cache = ForumBodyParagraphCache(
        maxEntries: 6,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final source = input.allocation.reference.content;
      final pin = cache.acquire(
        content: ForumBodyParagraphContent.anonymousInline(
          identity: source.identity,
          fontRevision: 'other-pin',
          styleRevision: source.styleRevision,
          style: source.style,
        ),
        width: 140,
      );
      final job = visibleJob(
        input,
        cache,
        prefix: declared ? () => [pin] : null,
      );
      if (declared) {
        final builds = cache.layoutBuildCount;
        expect(
          () => finishVisible(job),
          throwsA(
            isA<ForumBodyParagraphBudgetException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphBudgetFailure.content,
            ),
          ),
        );
        expect(cache.layoutBuildCount, builds);
        expect(cache.activeLeases, 1);
        pin.release();
      } else {
        var waiting = false;
        for (var n = 0; !waiting && n < 20000; n++) {
          waiting = job.advance(maxParts: 1).waitingForLayoutBudget;
        }
        expect(waiting, isTrue);
        final counts = (cache.layoutBuildCount, cache.pictureBuildCount);
        expect(job.advance(maxParts: 1).waitingForLayoutBudget, isTrue);
        expect((cache.layoutBuildCount, cache.pictureBuildCount), counts);
        pin.release();
        finishVisible(job).close();
      }
      expect(cache.activeLeases, 0);
    });
  }
  test(
    'scene planning borrows current phases without touching cache counters or leases',
    () {
      final c = _Context(), cache = c.fixture.cache;
      final counters = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.activeLeases,
      );
      final input = _finish(c.job());
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.activeLeases,
      ), counters);
      expect(input.allocation, same(c.allocation));
      expect(
        input.pictureInput.commands,
        hasLength(3 + c.allocation.marks.length),
      );
      final probe = cache.createBudgetProbe(captureInputEstimates: true);
      try {
        input.includeBudget(probe);
        final cost = probe.snapshotNativeEstimates().single;
        expect(cost.estimatedBytes, input.pictureInput.estimatedBytes);
      } finally {
        probe.close();
      }
      cache.close();
      expect(input.pictureInput.estimatedBytes, greaterThan(0));
    },
  );
  test(
    'phase order and all-layer frame substitution cannot fabricate a scene',
    () {
      final c = _Context(), before = c.fixture.cache.activeLeases;
      expect(
        () => c.job(
          inputs: [
            for (final i in [1, 0, 2])
              (parent: c.phases[i], frames: c.tables[i]),
          ],
        ),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(
        () => c.job(
          inputs: [
            for (var i = 0; i < 3; i++)
              (parent: c.phases[i], frames: c.fixture.isolatedFrames),
          ],
        ),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(c.fixture.cache.activeLeases, before);
    },
  );
  test(
    'borrowed retirement and late owner retirement cannot publish a scene input',
    () {
      final c = _Context(), before = c.fixture.cache.activeLeases;
      var active = true;
      final job = c.job(
        owner: () {
          if (!active) throw StateError('Retired');
        },
      );
      while (!job.isReady) {
        job.advance(maxParts: 1);
      }
      active = false;
      expect(job.takeInput, throwsStateError);
      expect(c.fixture.cache.activeLeases, before);
      final second = c.job();
      c.phases[1].release();
      expect(() => second.advance(maxParts: 1), throwsStateError);
      expect(c.fixture.cache.activeLeases, before - 1);
      expect(c.phases[0].isActive, isTrue);
      expect(c.phases[2].isActive, isTrue);
    },
  );
  test('exact request checks reject changed scale and retired handles', () {
    final c = _Context(),
        lease = c.phases[0],
        content = c.allocation.paintInput.background;
    final before = c.fixture.cache.layoutBuildCount;
    expect(
      lease.matchesNativeInputs(
        content: content,
        width: 140,
        textScaler: TextScaler.noScaling,
        rowIsolationPitch: 256,
      ),
      isTrue,
    );
    expect(
      lease.matchesNativeInputs(
        content: content,
        width: 140,
        textScaler: TextScaler.linear(1.2),
        rowIsolationPitch: 256,
      ),
      isFalse,
    );
    expect(c.fixture.cache.layoutBuildCount, before);
    lease.release();
    expect(
      () => lease.matchesNativeInputs(
        content: content,
        width: 140,
        textScaler: TextScaler.noScaling,
        rowIsolationPitch: 256,
      ),
      throwsStateError,
    );
  });
}
