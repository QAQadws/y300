import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/services/thread_body_preparation_handoff.dart';
import 'package:y300/features/thread/presentation/thread_detail_prepared_body.dart';

void main() {
  test(
    'twenty handoffs admit safe manifests despite a tiny cache and pending floors',
    () {
      final store = ThreadDetailPreparedBodyStore(maxRetainedCodeUnits: 400);
      final handoff = ThreadBodyPreparationHandoff(store);
      handoff.begin(pid: 'waiting', identity: 'waiting');
      for (var floor = 0; floor < 20; floor++) {
        final body = _body('floor-$floor');
        expect(handoff.canReserve('floor-$floor', body), isTrue);
        final lease = handoff.begin(
          pid: 'floor-$floor',
          identity: body.request.identity,
        );
        expect(
          handoff.complete(lease, body, currentInput: true),
          ThreadBodyPreparationHandoffResult.admitted,
        );
        expect(store.retainedCodeUnits, lessThanOrEqualTo(400));
      }
      expect(store.bodies, hasLength(20));
      expect(handoff.pendingFor('waiting'), isNotNull);
      expect(handoff.pendingFor('floor-19'), isNull);
    },
  );

  test(
    'planning selection never changes with chunk eviction or layout-only inputs',
    () {
      final store = ThreadDetailPreparedBodyStore(maxRetainedCodeUnits: 0);
      final handoff = ThreadBodyPreparationHandoff(store);
      final request = _body('floor').request.withPreparer(
        const DefaultForumHtmlRenderPreparer(
          enablePlainTextLinks: true,
          enableSafeDisplayPlanning: true,
        ),
      );
      final selected = handoff.selectPreparer(request);
      expect(selected, same(request.preparer));
      for (var floor = 0; floor < 20; floor++) {
        store.admit('other-$floor', _body('other-$floor'));
      }
      expect(handoff.selectPreparer(request), same(selected));
      final layout = request.preferences.copyWith(
        typography: request.preferences.typography.copyWith(
          fontScale: 1.7,
          lineHeightScale: 1.9,
        ),
      );
      final changed = ForumHtmlPreparationRequest(
        html: request.html,
        preferences: layout,
        theme: request.theme,
        sourceId: request.sourceId,
        threadId: request.threadId,
        imageCacheOwnerId: request.imageCacheOwnerId,
        preparer: request.preparer,
      );
      expect(handoff.selectPreparer(changed), same(selected));
      expect(changed.identity, request.identity);
      store.clear();
      handoff.clear();
      expect(handoff.selectPreparer(request), same(selected));
    },
  );

  test(
    'handoff seeds the middle or tail demand even when the body exceeds cache capacity',
    () {
      final body = _body('floor');
      final chunks = body.document.safeDisplayPlan!.chunks;
      final quota = chunks.first.html.length;
      expect(body.retainedCodeUnits, greaterThan(quota));
      for (final seed in [chunks.length ~/ 2, chunks.length - 1]) {
        final store = ThreadDetailPreparedBodyStore(
          maxRetainedCodeUnits: quota,
        );
        final handoff = ThreadBodyPreparationHandoff(store);
        final lease = handoff.begin(
          pid: 'floor',
          identity: body.request.identity,
        );
        expect(
          handoff.complete(lease, body, currentInput: true, seedOrdinal: seed),
          ThreadBodyPreparationHandoffResult.admitted,
        );
        final manifest = store['floor']!;
        expect(manifest.chunks, hasLength(chunks.length));
        expect(store.chunkFor(manifest, seed)!.html, chunks[seed].html);
        expect(store.chunkFor(manifest, 0), isNull);
        expect(store.cachedChunkCount, 1);
        expect(store.retainedCodeUnits, lessThanOrEqualTo(quota));
        expect(handoff.isDeclined('floor', body.request.identity), isFalse);
      }
    },
  );

  test('explicit preparation config and custom preparers remain untouched', () {
    final handoff = ThreadBodyPreparationHandoff(
      ThreadDetailPreparedBodyStore(maxRetainedCodeUnits: 0),
    );
    final request = _body('floor').request;
    const limited = DefaultForumHtmlRenderPreparer(
      enableSafeDisplayPlanning: true,
      safeDisplayPlanningCodeUnitBudget: 1234,
    );
    expect(
      handoff.selectPreparer(request.withPreparer(limited)),
      same(limited),
    );
    const custom = _CustomPreparer();
    expect(handoff.selectPreparer(request.withPreparer(custom)), same(custom));
  });

  test('retired A cannot release or publish a new A after A B A', () {
    final store = ThreadDetailPreparedBodyStore();
    final handoff = ThreadBodyPreparationHandoff(store);
    final a = _body('floor');
    final oldA = handoff.begin(pid: 'floor', identity: 'A');
    handoff.begin(pid: 'floor', identity: 'B');
    final newA = handoff.begin(pid: 'floor', identity: 'A');
    expect(handoff.release(oldA), isFalse);
    expect(
      handoff.complete(oldA, a, currentInput: true),
      ThreadBodyPreparationHandoffResult.retired,
    );
    expect(handoff.pendingFor('floor'), same(newA));
    expect(store['floor'], isNull);
    expect(
      handoff.complete(newA, a, currentInput: true),
      ThreadBodyPreparationHandoffResult.admitted,
    );
    expect(store['floor']!.identity, a.request.identity);
  });

  test(
    'owner retirement and current-input checks reject late equal identities',
    () {
      final store = ThreadDetailPreparedBodyStore();
      final handoff = ThreadBodyPreparationHandoff(store);
      final body = _body('floor');
      final previous = handoff.begin(pid: 'floor', identity: 'same');
      handoff.clear();
      final current = handoff.begin(pid: 'floor', identity: 'same');
      expect(
        handoff.complete(previous, body, currentInput: true),
        ThreadBodyPreparationHandoffResult.retired,
      );
      expect(handoff.pendingFor('floor'), same(current));
      expect(
        handoff.complete(current, body, currentInput: false),
        ThreadBodyPreparationHandoffResult.retired,
      );
      expect(store['floor'], isNull);
      expect(handoff.pendingFor('floor'), isNull);
    },
  );

  test(
    'same-input mismatched projection retires without changing the published manifest',
    () {
      final store = ThreadDetailPreparedBodyStore();
      final handoff = ThreadBodyPreparationHandoff(store);
      final body = _body('floor');
      store.admit('floor', body);
      final manifest = store['floor']!;
      final cached = store.chunkFor(manifest, 0)!;
      final plan = body.document.safeDisplayPlan!;
      final first = plan.chunks.first;
      final altered = ThreadDetailPreparedBody(
        request: body.request,
        document: body.document.copyWith(
          safeDisplayPlan: ForumHtmlSafeDisplayPlan(
            sourceHtml: plan.sourceHtml,
            sourceId: plan.sourceId,
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
        ),
      );
      final lease = handoff.begin(
        pid: 'floor',
        identity: body.request.identity,
      );
      expect(
        handoff.complete(lease, altered, currentInput: true),
        ThreadBodyPreparationHandoffResult.retired,
      );
      expect(store['floor'], same(manifest));
      expect(store.chunkFor(manifest, 0), same(cached));
      expect(handoff.isDeclined('floor', body.request.identity), isFalse);
      expect(handoff.pendingFor('floor'), isNull);
    },
  );

  test(
    'changed input that becomes whole removes stale entries and can recover',
    () {
      final store = ThreadDetailPreparedBodyStore(maxRetainedCodeUnits: 0);
      final handoff = ThreadBodyPreparationHandoff(store);
      final old = _body('floor');
      store.admit('floor', old);
      final changed = _body('floor', repeat: 22);
      final whole = ThreadDetailPreparedBody(
        request: changed.request,
        document: changed.document.copyWith(clearSafeDisplayPlan: true),
      );
      final rejected = handoff.begin(
        pid: 'floor',
        identity: changed.request.identity,
      );
      expect(
        handoff.complete(rejected, whole, currentInput: true),
        ThreadBodyPreparationHandoffResult.wholeFallback,
      );
      expect(store['floor'], isNull);
      expect(handoff.isDeclined('floor', changed.request.identity), isTrue);
      handoff.retireDeclinedInput('floor', old.request.identity);
      final retry = handoff.begin(pid: 'floor', identity: old.request.identity);
      expect(
        handoff.complete(retry, old, currentInput: true),
        ThreadBodyPreparationHandoffResult.admitted,
      );
      expect(store['floor']!.identity, old.request.identity);
      expect(store.retainedCodeUnits, 0);
    },
  );

  test(
    'new input drops only its old declined record and pruning retires pending leases',
    () {
      final store = ThreadDetailPreparedBodyStore();
      final handoff = ThreadBodyPreparationHandoff(store);
      final old = handoff.begin(pid: 'floor', identity: 'old');
      handoff.decline(old);
      handoff.retireDeclinedInput('floor', 'old');
      expect(handoff.isDeclined('floor', 'old'), isTrue);
      store.admit('floor', _body('floor'));
      final manifest = store['floor']!;
      final pending = handoff.begin(pid: 'floor', identity: 'new');
      handoff.retireDeclinedInput('floor', 'new');
      expect(handoff.isDeclined('floor', 'old'), isFalse);
      expect(handoff.pendingFor('floor'), same(pending));
      expect(store['floor'], same(manifest));
      handoff.retainPids({'another'});
      expect(handoff.pendingFor('floor'), isNull);
      expect(handoff.release(pending), isFalse);
    },
  );
}

ThreadDetailPreparedBody _body(String pid, {int repeat = 20}) {
  final theme = ThemeData.light();
  final request = ForumHtmlPreparationRequest(
    html: List.generate(
      16,
      (i) => 'line-${i.toString().padLeft(3, '0')} ${'字' * repeat}',
    ).join('<br>'),
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: const ForumHtmlRenderThemeFactory().fromMaterialTheme(
      theme: theme,
      surface: theme.colorScheme.surface,
    ),
    sourceId: pid,
    threadId: 'thread',
    imageCacheOwnerId: 'thread',
    preparer: const DefaultForumHtmlRenderPreparer(),
  );
  final document = request.prepareSynchronously();
  return ThreadDetailPreparedBody(
    request: request,
    document: document.copyWith(
      safeDisplayPlan: const ForumHtmlSafeDisplayPlanner(
        minCodeUnits: 0,
        targetChunkUnits: 4,
      ).plan(document),
    ),
  );
}

class _CustomPreparer extends DefaultForumHtmlRenderPreparer {
  const _CustomPreparer() : super(enableSafeDisplayPlanning: true);
}
