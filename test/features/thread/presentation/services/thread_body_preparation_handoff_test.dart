import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/services/thread_body_preparation_handoff.dart';
import 'package:y300/features/thread/presentation/thread_detail_prepared_body.dart';

void main() {
  test(
    'new floor skips planning when retained and pending floor slots are full',
    () {
      final store = ThreadDetailPreparedBodyStore(maxBodies: 4);
      final handoff = ThreadBodyPreparationHandoff(store);
      for (var index = 0; index < 3; index++) {
        store.admit('stored-$index', _body('stored-$index', 20));
      }
      final pending = _body('pending', 20);
      handoff.begin(
        pid: 'pending',
        identity: 'pending',
        reservedCodeUnits: pending.retainedCodeUnits,
      );
      final selected =
          handoff.selectPreparer(_planningRequest('fifth'))
              as DefaultForumHtmlRenderPreparer;
      expect(selected.enableSafeDisplayPlanning, isFalse);
      expect(selected.enablePlainTextLinks, isTrue);
      final updating =
          handoff.selectPreparer(_planningRequest('stored-0'))
              as DefaultForumHtmlRenderPreparer;
      expect(updating.enableSafeDisplayPlanning, isTrue);
      expect(
        updating.safeDisplayPlanningCodeUnitBudget,
        store.maxRetainedCodeUnits -
            store.retainedCodeUnits +
            store['stored-0']!.retainedCodeUnits -
            pending.retainedCodeUnits,
      );
    },
  );

  test(
    'request choice stays fixed across capacity and layout-only preference changes',
    () {
      final store = ThreadDetailPreparedBodyStore(maxBodies: 1);
      final handoff = ThreadBodyPreparationHandoff(store);
      final request = _planningRequest('waiting');
      final selected =
          handoff.selectPreparer(request) as DefaultForumHtmlRenderPreparer;
      expect(selected.enableSafeDisplayPlanning, isTrue);
      store.admit('another', _body('another', 20));
      expect(handoff.selectPreparer(request), same(selected));
      final layout = request.preferences.copyWith(
        typography: request.preferences.typography.copyWith(
          fontScale: 1.7,
          lineHeightScale: 1.9,
        ),
      );
      final layoutRequest = _planningRequest('waiting', preferences: layout);
      expect(handoff.selectPreparer(layoutRequest), same(selected));
      expect(
        layoutRequest.withPreparer(selected).identity,
        request.withPreparer(selected).identity,
      );
      final newInput = _planningRequest('waiting', html: '<p>new source</p>');
      final whole =
          handoff.selectPreparer(newInput) as DefaultForumHtmlRenderPreparer;
      expect(whole.enableSafeDisplayPlanning, isFalse);
      store.clear();
      expect(handoff.selectPreparer(newInput), same(whole));
      handoff.clear();
      final newOwner =
          handoff.selectPreparer(newInput) as DefaultForumHtmlRenderPreparer;
      expect(newOwner.enableSafeDisplayPlanning, isTrue);
      expect(newOwner, isNot(same(whole)));
    },
  );

  test(
    'byte allowance counts pending replacement growth without predicting raw HTML',
    () {
      final stored = _body('stored', 20);
      final growing = _body('stored', 64);
      final store = ThreadDetailPreparedBodyStore(
        maxRetainedCodeUnits: growing.retainedCodeUnits + 700,
      );
      store.admit('stored', stored);
      final handoff = ThreadBodyPreparationHandoff(store);
      handoff.begin(
        pid: 'stored',
        identity: 'growth',
        reservedCodeUnits: growing.retainedCodeUnits,
      );
      final selected =
          handoff.selectPreparer(_planningRequest('new', html: 'x'))
              as DefaultForumHtmlRenderPreparer;
      expect(selected.enableSafeDisplayPlanning, isTrue);
      expect(selected.safeDisplayPlanningCodeUnitBudget, 700);
      handoff.retainPids({'stored'});
      handoff.release(handoff.pendingFor('stored')!);
      final fresh =
          handoff.selectPreparer(_planningRequest('new', html: 'x'))
              as DefaultForumHtmlRenderPreparer;
      expect(
        fresh.safeDisplayPlanningCodeUnitBudget,
        store.maxRetainedCodeUnits - stored.retainedCodeUnits,
      );
    },
  );

  test(
    'explicit allowance is preserved and unknown preparers stay untouched',
    () {
      final handoff = ThreadBodyPreparationHandoff(
        ThreadDetailPreparedBodyStore(),
      );
      final request = _planningRequest('floor');
      final limited = request.withPreparer(
        const DefaultForumHtmlRenderPreparer(
          enableSafeDisplayPlanning: true,
          safeDisplayPlanningCodeUnitBudget: 1234,
        ),
      );
      final selected =
          handoff.selectPreparer(limited) as DefaultForumHtmlRenderPreparer;
      expect(selected.safeDisplayPlanningCodeUnitBudget, 1234);
      expect(selected.enablePlainTextLinks, isFalse);
      const custom = _CustomPreparer();
      expect(
        handoff.selectPreparer(request.withPreparer(custom)),
        same(custom),
      );
      const disabled = DefaultForumHtmlRenderPreparer();
      expect(
        handoff.selectPreparer(request.withPreparer(disabled)),
        same(disabled),
      );
    },
  );

  test(
    'new input releases declined identity without touching pending or store',
    () {
      final store = ThreadDetailPreparedBodyStore();
      final handoff = ThreadBodyPreparationHandoff(store);
      final oldBody = _body('floor', 20);
      final oldIdentity = oldBody.request.identity;
      final declined = handoff.begin(
        pid: 'floor',
        identity: oldIdentity,
        reservedCodeUnits: 0,
      );
      handoff.decline(declined);
      handoff.retireDeclinedInput('floor', oldIdentity);
      expect(handoff.isDeclined('floor', oldIdentity), isTrue);

      final newBody = _body('floor', 8);
      final newIdentity = newBody.request.identity;
      expect(store.admit('floor', newBody), isTrue);
      final pending = handoff.begin(
        pid: 'floor',
        identity: newIdentity,
        reservedCodeUnits: newBody.retainedCodeUnits,
      );
      handoff.retireDeclinedInput('floor', newIdentity);
      expect(handoff.isDeclined('floor', oldIdentity), isFalse);
      expect(handoff.isDeclined('floor', newIdentity), isFalse);
      expect(handoff.pendingFor('floor'), same(pending));
      expect(store['floor'], same(newBody));
      expect(store.retainedCodeUnits, newBody.retainedCodeUnits);
    },
  );

  test('removed floors release pending and declined input identities', () {
    final handoff = ThreadBodyPreparationHandoff(
      ThreadDetailPreparedBodyStore(),
    );
    final lease = handoff.begin(
      pid: 'removed',
      identity: 'old',
      reservedCodeUnits: 1,
    );
    handoff.decline(lease);
    final pending = handoff.begin(
      pid: 'pending',
      identity: 'old',
      reservedCodeUnits: 1,
    );
    handoff.retainPids({'remaining'});
    expect(handoff.isDeclined('removed', 'old'), isFalse);
    expect(handoff.isCurrent(pending), isFalse);
    expect(handoff.pendingFor('pending'), isNull);
  });
  test('retired A cannot clear or complete a new A after A -> B -> A', () {
    final store = ThreadDetailPreparedBodyStore();
    final handoff = ThreadBodyPreparationHandoff(store);
    final a = _body('floor', 20);
    final b = _body('floor', 21);
    final oldA = handoff.begin(
      pid: 'floor',
      identity: 'A',
      reservedCodeUnits: a.retainedCodeUnits,
    );
    handoff.begin(
      pid: 'floor',
      identity: 'B',
      reservedCodeUnits: b.retainedCodeUnits,
    );
    final newA = handoff.begin(
      pid: 'floor',
      identity: 'A',
      reservedCodeUnits: a.retainedCodeUnits,
    );
    expect(
      handoff.complete(oldA, a, currentInput: true),
      ThreadBodyPreparationHandoffResult.retired,
    );
    expect(handoff.release(oldA), isFalse);
    expect(handoff.pendingFor('floor'), same(newA));
    expect(store['floor'], isNull);
    expect(
      handoff.complete(newA, a, currentInput: true),
      ThreadBodyPreparationHandoffResult.admitted,
    );
    expect(store['floor'], same(a));
    expect(handoff.pendingFor('floor'), isNull);
  });

  test(
    'owner retirement isolates a later equal identity and stale input does not admit',
    () {
      final store = ThreadDetailPreparedBodyStore();
      final handoff = ThreadBodyPreparationHandoff(store);
      final body = _body('floor', 20);
      final oldOwner = handoff.begin(
        pid: 'floor',
        identity: 'same',
        reservedCodeUnits: body.retainedCodeUnits,
      );
      handoff.clear();
      final current = handoff.begin(
        pid: 'floor',
        identity: 'same',
        reservedCodeUnits: body.retainedCodeUnits,
      );
      expect(
        handoff.complete(oldOwner, body, currentInput: true),
        ThreadBodyPreparationHandoffResult.retired,
      );
      expect(handoff.pendingFor('floor'), same(current));
      expect(
        handoff.complete(current, body, currentInput: false),
        ThreadBodyPreparationHandoffResult.retired,
      );
      expect(store.bodies, isEmpty);
      expect(handoff.pendingFor('floor'), isNull);
    },
  );

  test(
    'replacement counts other pending reservations and can fall back then recover',
    () {
      final oldA = _body('a', 20);
      final oldB = _body('b', 20);
      final newC = _body('c', 8);
      final replacementA = _body('a', 64);
      final budget =
          oldA.retainedCodeUnits +
          oldB.retainedCodeUnits +
          replacementA.retainedCodeUnits -
          oldA.retainedCodeUnits +
          10;
      final store = ThreadDetailPreparedBodyStore(maxRetainedCodeUnits: budget);
      expect(store.admit('a', oldA), isTrue);
      expect(store.admit('b', oldB), isTrue);
      final handoff = ThreadBodyPreparationHandoff(store);
      expect(handoff.canReserve('c', newC), isTrue);
      final cLease = handoff.begin(
        pid: 'c',
        identity: 'c',
        reservedCodeUnits: newC.retainedCodeUnits,
      );
      expect(store.canAdmit('a', replacementA), isTrue);
      expect(handoff.canReserve('a', replacementA), isFalse);
      final rejected = handoff.begin(
        pid: 'a',
        identity: 'larger-a',
        reservedCodeUnits: 0,
      );
      handoff.decline(rejected);
      expect(store['a'], isNull);
      expect(store['b'], same(oldB));
      expect(handoff.isDeclined('a', 'larger-a'), isTrue);
      expect(
        handoff.complete(cLease, newC, currentInput: true),
        ThreadBodyPreparationHandoffResult.admitted,
      );
      expect(handoff.canReserve('a', oldA), isTrue);
      final recovered = handoff.begin(
        pid: 'a',
        identity: 'new-input',
        reservedCodeUnits: oldA.retainedCodeUnits,
      );
      expect(
        handoff.complete(recovered, oldA, currentInput: true),
        ThreadBodyPreparationHandoffResult.admitted,
      );
      expect(store['a'], same(oldA));
      expect(handoff.isDeclined('a', 'larger-a'), isFalse);
      expect(store.retainedCodeUnits, lessThanOrEqualTo(budget));
    },
  );

  test(
    'a final admission failure removes the stale body instead of leaving spinner-only chunks',
    () {
      final oldA = _body('a', 20);
      final oldB = _body('b', 20);
      final replacementA = _body('a', 64);
      final competing = _body('c', 8);
      final store = ThreadDetailPreparedBodyStore(
        maxRetainedCodeUnits:
            oldB.retainedCodeUnits + replacementA.retainedCodeUnits + 10,
      );
      store.admit('a', oldA);
      store.admit('b', oldB);
      final handoff = ThreadBodyPreparationHandoff(store);
      expect(handoff.canReserve('a', replacementA), isTrue);
      final lease = handoff.begin(
        pid: 'a',
        identity: 'replacement',
        reservedCodeUnits: replacementA.retainedCodeUnits,
      );
      expect(store.admit('c', competing), isTrue);
      expect(
        handoff.complete(lease, replacementA, currentInput: true),
        ThreadBodyPreparationHandoffResult.wholeFallback,
      );
      expect(store['a'], isNull);
      expect(store['b'], same(oldB));
      expect(store['c'], same(competing));
      expect(handoff.pendingFor('a'), isNull);
      expect(handoff.isDeclined('a', 'replacement'), isTrue);
    },
  );

  test(
    'pending floor entries are bounded and a pending shrink does not lend budget',
    () {
      final body = _body('a', 20);
      final store = ThreadDetailPreparedBodyStore(maxBodies: 1);
      final handoff = ThreadBodyPreparationHandoff(store);
      handoff.begin(
        pid: 'a',
        identity: 'a',
        reservedCodeUnits: body.retainedCodeUnits,
      );
      expect(handoff.canReserve('b', _body('b', 8)), isFalse);

      final full = _body('a', 128);
      final small = _body('a', 8);
      final bounded = ThreadDetailPreparedBodyStore(
        maxRetainedCodeUnits: full.retainedCodeUnits,
      );
      bounded.admit('a', full);
      final shrink = ThreadBodyPreparationHandoff(bounded);
      final lease = shrink.begin(
        pid: 'a',
        identity: 'shrink',
        reservedCodeUnits: small.retainedCodeUnits,
      );
      expect(shrink.canReserve('b', small), isFalse);
      expect(
        shrink.complete(lease, small, currentInput: true),
        ThreadBodyPreparationHandoffResult.admitted,
      );
      expect(shrink.canReserve('b', small), isTrue);
    },
  );
}

ThreadDetailPreparedBody _body(String pid, int repeat) {
  final materialTheme = ThemeData.light();
  final request = ForumHtmlPreparationRequest(
    html: List.generate(16, (i) => 'line-$i ${'字' * repeat}').join('<br>'),
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: const ForumHtmlRenderThemeFactory().fromMaterialTheme(
      theme: materialTheme,
      surface: materialTheme.colorScheme.surface,
    ),
    sourceId: pid,
    threadId: 'thread',
    imageCacheOwnerId: 'thread',
    preparer: const DefaultForumHtmlRenderPreparer(),
  );
  final document = request.prepareSynchronously();
  final plan = const ForumHtmlSafeDisplayPlanner(
    minCodeUnits: 0,
    targetChunkUnits: 4,
  ).plan(document);
  return ThreadDetailPreparedBody(
    request: request,
    document: document.copyWith(safeDisplayPlan: plan),
  );
}

ForumHtmlPreparationRequest _planningRequest(
  String pid, {
  String? html,
  ForumHtmlReaderPreferences? preferences,
}) {
  final base = _body(pid, 20).request;
  return ForumHtmlPreparationRequest(
    html: html ?? base.html,
    preferences: preferences ?? base.preferences,
    theme: base.theme,
    sourceId: pid,
    threadId: base.threadId,
    imageCacheOwnerId: base.imageCacheOwnerId,
    preparer: const DefaultForumHtmlRenderPreparer(
      enablePlainTextLinks: true,
      enableSafeDisplayPlanning: true,
    ),
  );
}

class _CustomPreparer extends DefaultForumHtmlRenderPreparer {
  const _CustomPreparer() : super(enableSafeDisplayPlanning: true);
}
