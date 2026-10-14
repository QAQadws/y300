import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/thread_detail_prepared_body.dart';

void main() {
  test(
    'twenty manifests survive cumulative HTML above the bounded chunk cache',
    () {
      final store = ThreadDetailPreparedBodyStore();
      var transientUnits = 0;
      final manifests = <ThreadDetailBodyManifest>[];
      for (var floor = 0; floor < 20; floor++) {
        final body = _body('floor-$floor', units: 3000, repeat: 24);
        transientUnits += body.retainedCodeUnits;
        expect(store.canAdmit('floor-$floor', body), isTrue);
        expect(store.admit('floor-$floor', body), isTrue);
        manifests.add(store['floor-$floor']!);
        expect(store.retainedCodeUnits, lessThanOrEqualTo(2 * 1024 * 1024));
      }
      expect(transientUnits, greaterThan(2 * 1024 * 1024));
      expect(store.manifests, hasLength(20));
      for (var floor = 0; floor < 20; floor++) {
        expect(store['floor-$floor'], same(manifests[floor]));
        expect(store.isCurrent(manifests[floor]), isTrue);
        expect(manifests[floor].chunks, hasLength(63));
      }
      expect(() => store.bodies.clear(), throwsUnsupportedError);
    },
  );

  test(
    'immutable metadata replaces full plans and cached documents own one chunk',
    () {
      final body = _body('floor');
      final plan = body.document.safeDisplayPlan!;
      final manifest = ThreadDetailBodyManifest.fromPrepared(body);
      expect(manifest.request.identity, body.request.identity);
      expect(manifest.kind, plan.kind);
      expect(() => manifest.chunks.clear(), throwsUnsupportedError);
      // Public manifests expose only descriptors, never full prepared snapshots.
      expect(() => (manifest as dynamic).document, throwsNoSuchMethodError);
      expect(
        () => (manifest as dynamic).safeDisplayPlan,
        throwsNoSuchMethodError,
      );
      for (var ordinal = 0; ordinal < manifest.chunks.length; ordinal++) {
        final meta = manifest.chunks[ordinal];
        final chunk = plan.chunks[ordinal];
        expect(meta.ordinal, ordinal);
        expect(
          (meta.startUnit, meta.endUnit),
          (chunk.startUnit, chunk.endUnit),
        );
        expect(meta.hasTrailingContent, chunk.hasTrailingContent);
        expect(meta.htmlCodeUnits, chunk.html.length);
        expect(
          meta.fingerprint,
          sha256.convert(utf8.encode(chunk.html)).toString(),
        );
        expect(() => (meta as dynamic).html, throwsNoSuchMethodError);
        expect(() => (meta as dynamic).sourceHtml, throwsNoSuchMethodError);
      }
      final store = ThreadDetailPreparedBodyStore();
      store.admit('floor', body);
      final cached = store.chunkFor(store['floor']!, 0)!;
      expect(cached.html, plan.chunks.first.html);
      expect(cached.document.preparedHtml, cached.html);
      expect(cached.document.safeDisplayPlan, isNull);
      expect(cached.document.sequence.sourceId, 'floor');
      expect(cached.document.themeSignature, body.document.themeSignature);
      expect(() => (cached as dynamic).sourceHtml, throwsNoSuchMethodError);
    },
  );

  test(
    'tiny LRU promotes a read and refills while both floors remain qualified',
    () {
      final body = _body('a');
      final cost = body.document.safeDisplayPlan!.chunks.first.html.length;
      final store = ThreadDetailPreparedBodyStore(
        maxRetainedCodeUnits: cost * 2,
      );
      store.admit('a', body);
      final a = store['a']!;
      expect(store.chunkFor(a, 1), isNotNull);
      expect(store.chunkFor(a, 0), isNotNull);
      final other = _body('b', units: 8, tailRepeat: 500);
      expect(store.admit('b', other), isTrue);
      final b = store['b']!;
      expect(store.chunkFor(a, 0), isNotNull);
      expect(store.chunkFor(a, 1), isNull);
      expect(store.chunkFor(b, 0), isNotNull);
      expect(store.chunkFor(b, 1), isNull);
      expect(store.isCurrent(a), isTrue);
      expect(store.isCurrent(b), isTrue);
      expect(store.rememberPrepared(a, body, seedOrdinal: 3), isTrue);
      expect(store.chunkFor(a, 3), isNotNull);
      expect(store.chunkFor(a, 2), isNotNull);
      expect(store.chunkFor(a, 0), isNull);
      expect(store.isCurrent(b), isTrue);
      expect(store.retainedCodeUnits, lessThanOrEqualTo(cost * 2));
    },
  );

  test('a huge floor seeds a nearby window instead of becoming whole', () {
    final body = _body('huge', units: 18000, repeat: 140);
    expect(body.document.preparedHtml.length, greaterThan(2 * 1024 * 1024));
    final plan = body.document.safeDisplayPlan!;
    final seed = plan.chunks.length ~/ 2;
    final quota = plan.chunks[seed].html.length * 4;
    final store = ThreadDetailPreparedBodyStore(maxRetainedCodeUnits: quota);
    expect(store.admit('huge', body, seedOrdinal: seed), isTrue);
    final manifest = store['huge']!;
    expect(manifest.kind, isNot(ForumHtmlSafeDisplayPlanKind.whole));
    expect(manifest.chunks.length, plan.chunks.length);
    final cached = <int>[
      for (var ordinal = 0; ordinal < plan.chunks.length; ordinal++)
        if (store.chunkFor(manifest, ordinal) != null) ordinal,
    ];
    expect(cached, contains(seed));
    expect(cached.length, inInclusiveRange(2, 4));
    expect(cached.every((ordinal) => (ordinal - seed).abs() <= 2), isTrue);
    expect(store.chunkFor(manifest, 0), isNull);
    expect(store.chunkFor(manifest, plan.chunks.length - 1), isNull);
    expect(store.retainedCodeUnits, lessThanOrEqualTo(quota));
  });

  test('zero quota and oversized chunks do not revoke safe qualification', () {
    final body = _body('floor');
    for (final quota in [
      0,
      body.document.safeDisplayPlan!.chunks.first.html.length - 1,
    ]) {
      final store = ThreadDetailPreparedBodyStore(maxRetainedCodeUnits: quota);
      expect(store.admit('floor', body), isTrue);
      final manifest = store['floor']!;
      expect(store.isCurrent(manifest), isTrue);
      expect(manifest.chunks, isNotEmpty);
      expect(store.chunkFor(manifest, 0), isNull);
      expect(store.retainedCodeUnits, 0);
    }
  });

  test(
    'mismatched refill is atomic even when changed text keeps its length',
    () {
      final body = _body('floor');
      final store = ThreadDetailPreparedBodyStore();
      store.admit('floor', body);
      final manifest = store['floor']!;
      final original = store.chunkFor(manifest, 0)!;
      final cost = store.retainedCodeUnits;
      expect(store.rememberPrepared(manifest, _altered(body)), isFalse);
      expect(store.chunkFor(manifest, 0), same(original));
      expect(store.retainedCodeUnits, cost);
      expect(store['floor'], same(manifest));
      expect(store.rememberPrepared(manifest, _body('other')), isFalse);
      expect(store.rememberPrepared(manifest, body, seedOrdinal: -1), isFalse);
      expect(
        store.rememberPrepared(
          manifest,
          body,
          seedOrdinal: manifest.chunks.length,
        ),
        isFalse,
      );
      expect(store.chunkFor(manifest, 0), same(original));
    },
  );

  test(
    'replacement and owner clearing reject retired chunk and height writes',
    () {
      final store = ThreadDetailPreparedBodyStore();
      final a = _body('floor');
      store.admit('floor', a);
      final old = store['floor']!;
      store.activateHeightLayout(old, layoutIdentity: 'layout');
      store.rememberHeight(old, 0, layoutIdentity: 'layout', height: 31);
      final b = _body('floor', repeat: 22);
      store.admit('floor', b);
      final current = store['floor']!;
      expect(current, isNot(same(old)));
      expect(store.isCurrent(old), isFalse);
      expect(store.rememberPrepared(old, a), isFalse);
      store.rememberHeight(old, 0, layoutIdentity: 'layout', height: 999);
      expect(store.heightFor(current, 0, layoutIdentity: 'layout'), isNull);
      expect(store.chunkFor(old, 0), isNull);
      store.clear();
      expect(store.bodies, isEmpty);
      expect(store.retainedCodeUnits, 0);
      expect(store.rememberPrepared(current, b), isFalse);
    },
  );

  test(
    'layout activation clears old geometry and ignores late old layout heights',
    () {
      final store = ThreadDetailPreparedBodyStore();
      store.admit('floor', _body('floor'));
      final manifest = store['floor']!;
      store.activateHeightLayout(manifest, layoutIdentity: 'width-400-font-1');
      store.rememberHeight(
        manifest,
        0,
        layoutIdentity: 'width-400-font-1',
        height: 24,
      );
      store.rememberHeight(
        manifest,
        1,
        layoutIdentity: 'width-400-font-1',
        height: 36,
      );
      expect(
        store.heightFor(manifest, 1, layoutIdentity: 'width-400-font-1'),
        36,
      );
      expect(
        store.heightFor(manifest, 1, layoutIdentity: 'width-360-font-1.5'),
        isNull,
      );
      expect(
        store.heightFor(manifest, 1, layoutIdentity: 'width-400-font-1'),
        36,
      );
      store.activateHeightLayout(
        manifest,
        layoutIdentity: 'width-360-font-1.5',
      );
      expect(
        store.heightFor(manifest, 0, layoutIdentity: 'width-400-font-1'),
        isNull,
      );
      expect(
        store.heightFor(manifest, 1, layoutIdentity: 'width-360-font-1.5'),
        isNull,
      );
      store.rememberHeight(
        manifest,
        0,
        layoutIdentity: 'width-360-font-1.5',
        height: 48,
      );
      store.rememberHeight(
        manifest,
        0,
        layoutIdentity: 'width-400-font-1',
        height: 999,
      );
      expect(
        store.heightFor(manifest, 0, layoutIdentity: 'width-360-font-1.5'),
        48,
      );
      expect(
        store.heightFor(manifest, 0, layoutIdentity: 'width-400-font-1'),
        isNull,
      );
    },
  );

  test(
    'pruning removes retired floor values and preserves current geometry',
    () {
      final a = _body('a');
      final b = _body('b');
      final store = ThreadDetailPreparedBodyStore();
      store.admit('a', a);
      store.admit('b', b);
      final oldA = store['a']!;
      final currentB = store['b']!;
      store.rememberHeight(currentB, 0, layoutIdentity: 'layout', height: 25);
      store.retainWhere((pid, _) => pid != 'a');
      expect(store.bodies.keys, ['b']);
      expect(store.chunkFor(oldA, 0), isNull);
      expect(store.rememberPrepared(oldA, a), isFalse);
      expect(store.chunkFor(currentB, 0), isNotNull);
      expect(store.heightFor(currentB, 0, layoutIdentity: 'layout'), 25);
    },
  );

  test('whole or mismatched source cannot replace a valid manifest', () {
    final body = _body('floor');
    final whole = ThreadDetailPreparedBody(
      request: body.request,
      document: body.document.copyWith(clearSafeDisplayPlan: true),
    );
    expect(
      () => ThreadDetailBodyManifest.fromPrepared(whole),
      throwsArgumentError,
    );
    final store = ThreadDetailPreparedBodyStore();
    store.admit('floor', body);
    final manifest = store['floor'];
    expect(store.canAdmit('floor', whole), isFalse);
    expect(store.admit('floor', whole), isFalse);
    expect(store.admit('wrong-source', body), isFalse);
    expect(store['floor'], same(manifest));
  });
}

ThreadDetailPreparedBody _altered(ThreadDetailPreparedBody body) {
  final plan = body.document.safeDisplayPlan!;
  final first = plan.chunks.first;
  return ThreadDetailPreparedBody(
    request: body.request,
    document: body.document.copyWith(
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
    ),
  );
}

ThreadDetailPreparedBody _body(
  String pid, {
  int units = 16,
  int repeat = 20,
  int? tailRepeat,
}) {
  final materialTheme = ThemeData.light();
  final request = ForumHtmlPreparationRequest(
    html: [
      for (var index = 0; index < units; index++)
        'line-${index.toString().padLeft(5, '0')} ${'字' * (tailRepeat != null && index >= 4 ? tailRepeat : repeat)}',
    ].join('<br>'),
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
  return ThreadDetailPreparedBody(
    request: request,
    document: document.copyWith(
      safeDisplayPlan: ForumHtmlSafeDisplayPlanner(
        minCodeUnits: 0,
        targetChunkUnits: units >= 100 ? 48 : 4,
        maxChunkCodeUnits: 8192,
      ).plan(document),
    ),
  );
}
