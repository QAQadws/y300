import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/services/thread_body_chunk_preparation.dart';
import 'package:y300/features/thread/presentation/thread_detail_prepared_body.dart';

void main() {
  test(
    'cache hits do not start preparation and expose an independent clear-plan document',
    () async {
      final rig = _Rig(quota: 100000);
      addTearDown(rig.dispose);
      final body = _body('floor');
      final manifest = _admit(rig, body);
      final chunk = rig.service.resolve(Object(), manifest, 0)!;
      expect(rig.worker.calls, isEmpty);
      expect(chunk.html, body.document.safeDisplayPlan!.chunks.first.html);
      expect(chunk.document.safeDisplayPlan, isNull);
      expect(chunk.document.sequence.sourceId, 'floor');
    },
  );

  test(
    'same-floor misses share one worker and fan out even with zero LRU quota',
    () async {
      final rig = _Rig(quota: 0);
      addTearDown(rig.dispose);
      final body = _body('floor');
      final manifest = _admit(rig, body);
      final first = Object();
      final second = Object();
      expect(rig.service.resolve(first, manifest, 2), isNull);
      expect(rig.service.resolve(second, manifest, 10), isNull);
      expect(rig.worker.calls, hasLength(1));
      rig.worker.calls.single.succeed();
      await _flush();
      final a = rig.service.resolve(first, manifest, 2)!;
      final b = rig.service.resolve(second, manifest, 10)!;
      expect(a.html, body.document.safeDisplayPlan!.chunks[2].html);
      expect(b.html, body.document.safeDisplayPlan!.chunks[10].html);
      expect(a.document.safeDisplayPlan, isNull);
      expect(b.document.safeDisplayPlan, isNull);
      expect(rig.store.retainedCodeUnits, 0);
      expect(rig.store.isCurrent(manifest), isTrue);
      expect(rig.worker.calls, hasLength(1));
      rig.service.release(first);
      expect(rig.service.resolve(second, manifest, 10), same(b));
      rig.service.release(second);
      expect(rig.service.resolve(Object(), manifest, 10), isNull);
      expect(rig.worker.calls, hasLength(2));
      rig.worker.calls.last.succeed();
      await _flush();
    },
  );

  test('releasing one consumer preserves the shared live demand', () async {
    final rig = _Rig(quota: 0);
    addTearDown(rig.dispose);
    final manifest = _admit(rig, _body('floor'));
    final first = Object();
    final second = Object();
    rig.service.resolve(first, manifest, 1);
    rig.service.resolve(second, manifest, 9);
    rig.service.release(first);
    expect(rig.executor.activeCount, 1);
    expect(rig.worker.calls, hasLength(1));
    rig.worker.calls.single.succeed();
    await _flush();
    expect(rig.service.resolve(second, manifest, 9)!.ordinal, 9);
    expect(rig.service.errorFor(first), isNull);
    expect(rig.worker.calls, hasLength(1));
  });

  test(
    'last queued consumer releases executor queue admission immediately',
    () async {
      final rig = _Rig(quota: 0);
      addTearDown(rig.dispose);
      final blocker = rig.executor.tryAcquire(_body('blocker').request)!;
      final manifest = _admit(rig, _body('floor'));
      final consumer = Object();
      rig.service.resolve(consumer, manifest, 8);
      expect(rig.executor.activeCount, 1);
      expect(rig.executor.queuedCount, 1);
      expect(rig.worker.calls, hasLength(1));
      rig.service.release(consumer);
      expect(rig.executor.queuedCount, 0);
      expect(rig.executor.queuedCodeUnits, 0);
      rig.worker.calls.single.succeed();
      await blocker.future;
      blocker.release();
      await _flush();
      expect(rig.worker.calls, hasLength(1));
      expect(rig.store.chunkFor(manifest, 8), isNull);
    },
  );

  test(
    'running release remains active until real completion but cannot fill its late chunk',
    () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final manifest = _admit(rig, _body('floor'));
      final cachedHead = rig.store.chunkFor(manifest, 0)!;
      final consumer = Object();
      var notifications = 0;
      rig.service.addListener(() => notifications++);
      rig.service.resolve(consumer, manifest, 10);
      rig.service.release(consumer);
      expect(rig.executor.activeCount, 1);
      rig.worker.calls.single.succeed();
      await _flush();
      expect(rig.executor.activeCount, 0);
      expect(rig.store.chunkFor(manifest, 10), isNull);
      expect(rig.store.chunkFor(manifest, 0), same(cachedHead));
      expect(notifications, 0);
      expect(rig.store.isCurrent(manifest), isTrue);
    },
  );

  test(
    'owner clear prevents a late owner result from completing the new owner',
    () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final old = _admit(rig, _body('floor', owner: 'owner-a'));
      rig.service.resolve(Object(), old, 10);
      rig.service.clear();
      rig.store.clear();
      final current = _admit(rig, _body('floor', owner: 'owner-b'));
      final consumer = Object();
      expect(rig.service.resolve(consumer, current, 10), isNull);
      expect(rig.executor.queuedCount, 1);
      rig.worker.calls.first.succeed();
      await _flush();
      expect(rig.worker.calls, hasLength(2));
      expect(rig.store.chunkFor(current, 10), isNull);
      expect(rig.service.resolve(consumer, current, 10), isNull);
      expect(rig.store.chunkFor(old, 10), isNull);
      rig.worker.calls.last.succeed();
      await _flush();
      expect(rig.service.resolve(consumer, current, 10)!.ordinal, 10);
      expect(rig.store.isCurrent(current), isTrue);
    },
  );

  test(
    'A B A replaces manifest leases while equal pure input may reuse one real worker',
    () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final bodyA = _body('floor', prefix: 'A');
      final oldA = _admit(rig, bodyA);
      final oldConsumer = Object();
      rig.service.resolve(oldConsumer, oldA, 10);
      _admit(rig, _body('floor', prefix: 'B'));
      rig.service.retainCurrent();
      final newA = _admit(rig, bodyA);
      expect(newA, isNot(same(oldA)));
      final currentConsumer = Object();
      rig.service.resolve(currentConsumer, newA, 11);
      // The executor may share an unfinished pure preparation for exact input A;
      // only the new manifest's service lease may consume its completion.
      expect(rig.worker.calls, hasLength(1));
      rig.worker.calls.single.succeed();
      await _flush();
      expect(rig.service.resolve(currentConsumer, newA, 11)!.ordinal, 11);
      expect(rig.store.chunkFor(oldA, 11), isNull);
      expect(rig.store.chunkFor(newA, 11), isNotNull);
      expect(rig.service.errorFor(oldConsumer), isNull);
      expect(rig.store.isCurrent(newA), isTrue);
    },
  );

  test(
    'failures remain on one shared job until explicit retry starts one replacement',
    () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final manifest = _admit(rig, _body('floor'));
      final first = Object();
      final second = Object();
      rig.service.resolve(first, manifest, 8);
      rig.service.resolve(second, manifest, 10);
      final failure = StateError('controlled preparation failure');
      rig.worker.calls.single.fail(failure);
      await _flush();
      expect(rig.service.hasError(first), isTrue);
      expect(rig.service.errorFor(second), same(failure));
      for (var rebuild = 0; rebuild < 4; rebuild++) {
        expect(
          () => rig.service.resolve(first, manifest, 8),
          throwsA(same(failure)),
        );
      }
      expect(rig.worker.calls, hasLength(1));
      expect(rig.store['floor'], same(manifest));
      rig.service.retry(manifest);
      expect(rig.worker.calls, hasLength(2));
      expect(rig.service.errorFor(first), isNull);
      expect(rig.service.errorFor(second), isNull);
      rig.worker.calls.last.succeed();
      await _flush();
      expect(rig.service.resolve(first, manifest, 8)!.ordinal, 8);
      expect(rig.service.resolve(second, manifest, 10)!.ordinal, 10);
      expect(rig.store.retainedCodeUnits, lessThanOrEqualTo(5000));
    },
  );

  test(
    'same-length manifest mismatch preserves entries and retries against the original manifest',
    () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final body = _body('floor');
      final manifest = _admit(rig, body);
      final consumer = Object();
      rig.service.resolve(consumer, manifest, 10);
      rig.worker.calls.single.succeed(_altered(body.document));
      await _flush();
      expect(rig.service.hasError(consumer), isTrue);
      expect(
        () => rig.service.resolve(consumer, manifest, 10),
        throwsStateError,
      );
      expect(rig.store['floor'], same(manifest));
      expect(rig.store.chunkFor(manifest, 10), isNull);
      rig.service.retry(manifest);
      rig.worker.calls.last.succeed();
      await _flush();
      expect(
        rig.service.resolve(consumer, manifest, 10)!.html,
        body.document.safeDisplayPlan!.chunks[10].html,
      );
      expect(rig.store['floor'], same(manifest));
    },
  );

  test(
    'stale manifests and invalid ordinals cannot queue a new preparation',
    () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final old = _admit(rig, _body('floor', prefix: 'old'));
      final current = _admit(rig, _body('floor', prefix: 'new'));
      expect(rig.service.resolve(Object(), old, 10), isNull);
      expect(
        () => rig.service.resolve(Object(), current, -1),
        throwsRangeError,
      );
      expect(
        () => rig.service.resolve(Object(), current, current.chunks.length),
        throwsRangeError,
      );
      expect(rig.worker.calls, isEmpty);
    },
  );

  test('clear suppresses a queued previous-owner notification', () async {
    final rig = _Rig(threshold: 1 << 30);
    addTearDown(rig.dispose);
    final manifest = _admit(rig, _body('floor'));
    var notifications = 0;
    rig.service.addListener(() => notifications++);
    expect(rig.service.resolve(Object(), manifest, 10), isNotNull);
    rig.service.clear();
    await _flush();
    expect(notifications, 0);
    expect(rig.worker.calls, isEmpty);
  });

  test(
    'dispose permanently rejects new demands and late completion never fills the cache',
    () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final manifest = _admit(rig, _body('floor'));
      rig.service.resolve(Object(), manifest, 10);
      rig.service.dispose();
      rig.worker.calls.single.succeed();
      await _flush();
      expect(rig.store.chunkFor(manifest, 10), isNull);
      expect(
        () => rig.service.resolve(Object(), manifest, 10),
        throwsStateError,
      );
    },
  );
}

class _Rig {
  _Rig({int quota = 5000, int threshold = 0}) {
    store = ThreadDetailPreparedBodyStore(maxRetainedCodeUnits: quota);
    executor = ForumHtmlPreparationExecutor(
      codeUnitThreshold: threshold,
      worker: worker.prepare,
    );
    service = ThreadBodyChunkPreparation(store, executor: executor);
  }
  final worker = _ControlledWorker();
  late final ThreadDetailPreparedBodyStore store;
  late final ForumHtmlPreparationExecutor executor;
  late final ThreadBodyChunkPreparation service;
  Future<void> dispose() async {
    service.dispose();
    for (final call in worker.calls) {
      if (!call.completer.isCompleted) call.succeed();
    }
    await _flush();
    executor.dispose();
  }
}

class _ControlledWorker {
  final calls = <_PendingPreparation>[];
  Future<ForumHtmlPreparedRenderDocument> prepare(
    ForumHtmlBackgroundPreparationInput input,
  ) {
    final call = _PendingPreparation(input);
    calls.add(call);
    return call.completer.future;
  }
}

class _PendingPreparation {
  _PendingPreparation(this.input);
  final ForumHtmlBackgroundPreparationInput input;
  final completer = Completer<ForumHtmlPreparedRenderDocument>();
  void succeed([ForumHtmlPreparedRenderDocument? document]) =>
      completer.complete(document ?? input.prepare());
  void fail(Object error) => completer.completeError(error, StackTrace.current);
}

Future<void> _flush() async {
  for (var turn = 0; turn < 3; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ThreadDetailBodyManifest _admit(_Rig rig, ThreadDetailPreparedBody body) {
  expect(rig.store.admit(body.request.sourceId, body), isTrue);
  return rig.store[body.request.sourceId]!;
}

ThreadDetailPreparedBody _body(
  String pid, {
  String prefix = 'body',
  String owner = 'thread',
}) {
  final theme = ThemeData.light();
  final request = ForumHtmlPreparationRequest(
    html: List.generate(
      600,
      (i) => '$prefix-line-${i.toString().padLeft(3, '0')} ${'字' * 72}',
    ).join('<br>'),
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: const ForumHtmlRenderThemeFactory().fromMaterialTheme(
      theme: theme,
      surface: theme.colorScheme.surface,
    ),
    sourceId: pid,
    threadId: owner,
    imageCacheOwnerId: owner,
    preparer: const DefaultForumHtmlRenderPreparer(
      enableSafeDisplayPlanning: true,
    ),
  );
  return ThreadDetailPreparedBody(
    request: request,
    document: request.prepareSynchronously(),
  );
}

ForumHtmlPreparedRenderDocument _altered(
  ForumHtmlPreparedRenderDocument document,
) {
  final plan = document.safeDisplayPlan!;
  final first = plan.chunks.first;
  return document.copyWith(
    safeDisplayPlan: ForumHtmlSafeDisplayPlan(
      sourceId: plan.sourceId,
      sourceHtml: plan.sourceHtml,
      kind: plan.kind,
      chunks: [
        ForumHtmlDisplayChunk(
          ordinal: first.ordinal,
          html: first.html.replaceFirst('字', '错'),
          hasTrailingContent: first.hasTrailingContent,
          sourceId: first.sourceId,
          sourceHtml: first.sourceHtml,
          startUnit: first.startUnit,
          endUnit: first.endUnit,
        ),
        ...plan.chunks.skip(1),
      ],
    ),
  );
}
