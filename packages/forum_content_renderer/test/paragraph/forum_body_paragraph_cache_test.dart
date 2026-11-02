import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyParagraphContent content(
  String html, {
  double after = 10,
  String fontRevision = 'loaded',
  Color color = const Color(0xff000000),
  ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'cache',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: TextStyle(
        fontSize: 20,
        height: 1.5,
        fontFamily: 'Ahem',
        color: color,
      ),
      fontRevision: fontRevision,
      paragraphAfter: after,
      linkColor: const Color(0xff0000ff),
    ),
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: styles,
    path: '0',
    layoutMode: layoutMode,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native input identities are readonly pure values without live ownership',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      final input = content('<p>ab</p>');
      final lease = cache.acquire(content: input, width: 100);
      final key = lease.nativeInputIdentity;
      final builds = cache.layoutBuildCount;
      final probe = cache.createBudgetProbe();
      probe.include(
        content: input,
        width: 100,
        minimumLineCount: 1,
        textScaler: TextScaler.noScaling,
      );
      final keys = probe.snapshotNativeIdentities();
      expect(keys, {key});
      expect(cache.layoutBuildCount, builds);
      expect(cache.activeLeases, 1);
      expect(() => keys.clear(), throwsUnsupportedError);
      probe.close();
      expect(() => probe.snapshotNativeIdentities(), throwsStateError);
      lease.release();
      cache.close();
      expect(keys.contains(key), isTrue);
      expect(cache.estimatedRetainedBytes, 0);
      expect(() => lease.nativeInputIdentity, throwsStateError);
    },
  );

  test(
    'intrinsic layouts reuse natural geometry across valid request widths only',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = content(
        '<p>abc</p>',
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      final first = cache.acquire(content: input, width: 20);
      final second = cache.acquire(content: input, width: 200);
      final wrapped = cache.acquire(content: content('<p>abc</p>'), width: 60);
      final fitted = cache.acquire(
        content: content(
          '<p>abc</p>',
          layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
        ),
        width: 60,
      );
      expect(first.layout, same(second.layout));
      expect(first.layout.width, 60);
      expect(first.layout.height, wrapped.layout.height);
      expect(first.layout, isNot(same(wrapped.layout)));
      expect(first.layout, isNot(same(fitted.layout)));
      expect(cache.layoutBuildCount, 3);
      expect(
        () => cache.acquire(content: input, width: 0),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      for (final lease in [first, second, wrapped, fitted]) {
        lease.release();
      }
      cache.close();
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'fitted and wrapped layouts never alias even when neither needs to shrink',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final wrapped = cache.acquire(content: content('<p>ab</p>'), width: 100);
      final fitted = cache.acquire(
        content: content(
          '<p>ab</p>',
          layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
        ),
        width: 100,
      );
      final alias = cache.acquire(
        content: content(
          '<p>ab</p>',
          layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
        ),
        width: 100,
      );
      expect(fitted.layout.height, wrapped.layout.height);
      expect(fitted.layout, isNot(same(wrapped.layout)));
      expect(alias.layout, same(fitted.layout));
      expect(cache.layoutBuildCount, 2);
      expect(cache.hitCount, 1);
      wrapped.release();
      fitted.release();
      alias.release();
      cache.close();
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'release revisions are synchronous while budget events cannot reenter mutation',
    () async {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final changes = <int>[];
      var insideRelease = false;
      final done = Completer<void>();
      final subscription = cache.budgetChanges.listen((revision) {
        expect(insideRelease, isFalse);
        changes.add(revision);
      }, onDone: done.complete);
      addTearDown(subscription.cancel);
      final input = content('<p>abc</p>');
      final first = cache.acquire(content: input, width: 100);
      final alias = cache.acquire(content: input, width: 100);
      expect(cache.budgetRevision, 0);
      insideRelease = true;
      first.release();
      insideRelease = false;
      expect(cache.budgetRevision, 1);
      expect(changes, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(changes, [1]);
      expect(alias.isActive, isTrue);
      alias.release();
      expect(cache.budgetRevision, 2);
      cache.close();
      expect(cache.budgetRevision, 3);
      await done.future;
      expect(changes, [1, 2, 3]);
      alias.release();
      cache.close();
      expect(cache.budgetRevision, 3);
      expect(await cache.budgetChanges.toList(), isEmpty);
    },
  );

  test(
    'budget consumers can independently unsubscribe without affecting leases',
    () async {
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final firstEvents = <int>[];
      final secondEvents = <int>[];
      final first = cache.budgetChanges.listen(firstEvents.add);
      final second = cache.budgetChanges.listen(secondEvents.add);
      addTearDown(second.cancel);
      final input = content('<p>a</p>');
      final one = cache.acquire(content: input, width: 100);
      final two = cache.acquire(content: input, width: 100);
      one.release();
      await Future<void>.delayed(Duration.zero);
      await first.cancel();
      two.release();
      await Future<void>.delayed(Duration.zero);
      expect(firstEvents, [1]);
      expect(secondEvents, [1, 2]);
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'asynchronous budget listeners may safely retire or reacquire the owner',
    () async {
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final done = Completer<void>();
      final subscription = cache.budgetChanges.listen((revision) {
        if (revision != 1) return;
        final lease = cache.acquire(content: content('<p>b</p>'), width: 100);
        expect(lease.isActive, isTrue);
        cache.close();
        expect(lease.isActive, isFalse);
      }, onDone: done.complete);
      addTearDown(subscription.cancel);
      cache.acquire(content: content('<p>a</p>'), width: 100).release();
      await done.future;
      expect(cache.isClosed, isTrue);
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'cache-only admission acquires warm layouts but never builds on a miss',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = content('<p>abc</p>');
      expect(cache.tryAcquireCached(content: input, width: 100), isNull);
      expect(cache.layoutBuildCount, 0);
      final lease = cache.acquire(content: input, width: 100);
      final cached = cache.tryAcquireCached(content: input, width: 100)!;
      expect(cached.layout, same(lease.layout));
      expect(cache.tryAcquireCached(content: input, width: 101), isNull);
      expect(cache.layoutBuildCount, 1);
      expect(
        () => cache.tryAcquireCached(content: input, width: 0),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      lease.release();
      cached.release();
      expect(cache.activeLeases, 0);
    },
  );

  test('equal paint text does not reuse a different source projection', () {
    final document = const ForumBodyParser().parse(
      html: '<p><span>a</span><span>a</span></p>',
      sourceId: 'projection-cache',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(
      document,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(fontSize: 20),
        fontRevision: 'loaded',
        linkColor: const Color(0xff0000ff),
      ),
    );
    ForumBodyParagraphContent hide(String path) {
      final original = styles.byPath[path]!;
      return const ForumBodyParagraphContentBuilder().build(
        document: document,
        path: '0',
        styles: ForumBodyStyleResult(
          identity: styles.identity,
          fontRevision: styles.fontRevision,
          root: styles.root,
          resolverRevision: styles.resolverRevision,
          issues: styles.issues,
          byPath: {
            ...styles.byPath,
            path: ForumBodyResolvedStyle(
              textStyle: original.textStyle,
              role: original.role,
              textAlign: original.textAlign,
              textDirection: original.textDirection,
              hidden: true,
            ),
          },
        ),
      );
    }

    final firstContent = hide('0/0');
    final secondContent = hide('0/1');
    expect(firstContent.textSpan, secondContent.textSpan);
    expect(firstContent.projection.sourceAtUtf16(0).sourceRune, 1);
    expect(secondContent.projection.sourceAtUtf16(0).sourceRune, 0);
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final first = cache.acquire(content: firstContent, width: 200);
    final second = cache.acquire(content: secondContent, width: 200);
    expect(second.layout.projection.sourceAtUtf16(0).sourceRune, 0);
    expect(identical(first.layout, second.layout), isFalse);
    first.release();
    second.release();
  });

  test(
    'value-equal requests share native layout with separate view leases',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final first = cache.acquire(content: content('<p>abc</p>'), width: 200);
      final second = cache.acquire(content: content('<p>abc</p>'), width: 200);
      expect(identical(first.layout, second.layout), isTrue);
      expect(cache.layoutBuildCount, 1);
      expect(cache.hitCount, 1);
      expect(cache.activeLeases, 2);
      first.release();
      first.release();
      expect(cache.activeLeases, 1);
      expect(second.layout.isDisposed, isFalse);
      expect(() => first.layout, throwsStateError);
      second.release();
      expect(cache.activeLeases, 0);
      expect(cache.entryCount, 1);
    },
  );

  test(
    'box-only metadata changes reuse layout without returning stale spacing',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final first = cache.acquire(content: content('<p>abc</p>'), width: 200);
      final second = cache.acquire(
        content: content('<p>abc</p>', after: 42),
        width: 200,
      );
      expect(identical(first.layout, second.layout), isTrue);
      expect(first.content.style.margin.bottom.value, 10);
      expect(second.content.style.margin.bottom.value, 42);
      first.release();
      second.release();
    },
  );

  test(
    'LRU evicts only unpinned values and disposes their native resource',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final a = cache.acquire(content: content('<p>a</p>'), width: 200);
      final aLayout = a.layout;
      a.release();
      final b = cache.acquire(content: content('<p>b</p>'), width: 200);
      final c = cache.acquire(content: content('<p>c</p>'), width: 200);
      expect(aLayout.isDisposed, isTrue);
      expect(b.layout.isDisposed, isFalse);
      expect(c.layout.isDisposed, isFalse);
      expect(cache.entryCount, 2);
      b.release();
      c.release();
      cache.clearUnpinned();
      expect(cache.entryCount, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test('pinned or byte budget pressure does not discard a readable layout', () {
    for (final (count, bytes) in [(1, 1 << 20), (2, 5000)]) {
      final cache = ForumBodyParagraphCache(
        maxEntries: count,
        maxEstimatedBytes: bytes,
      );
      final first = cache.acquire(content: content('<p>abc</p>'), width: 200);
      final old = first.layout;
      expect(
        () => cache.acquire(content: content('<p>defgh</p>'), width: 200),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.pinned,
          ),
        ),
      );
      expect(cache.layoutBuildCount, 1);
      expect(old.isDisposed, isFalse);
      first.release();
      final next = cache.acquire(content: content('<p>defgh</p>'), width: 200);
      expect(old.isDisposed, isTrue);
      expect(cache.estimatedRetainedBytes, lessThanOrEqualTo(bytes));
      next.release();
      cache.close();
    }
  });

  test(
    'actual nonlinear outputs identify layouts rather than a scalar estimate',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 3,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = content('<p>a<span style="font-size:40px">b</span></p>');
      final a = cache.acquire(
        content: input,
        width: 200,
        textScaler: const _Scaler(1.25),
      );
      final same = cache.acquire(
        content: input,
        width: 200,
        textScaler: const _Scaler(1.25),
      );
      final different = cache.acquire(
        content: input,
        width: 200,
        textScaler: const _Scaler(1.5),
      );
      expect(identical(a.layout, same.layout), isTrue);
      expect(identical(a.layout, different.layout), isFalse);
      expect(cache.layoutBuildCount, 2);
      a.release();
      same.release();
      different.release();
    },
  );

  test('font revision, width and baked paint each invalidate native input', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final leases = [
      cache.acquire(content: content('<p>abc</p>'), width: 200),
      cache.acquire(
        content: content('<p>abc</p>', fontRevision: 'reloaded'),
        width: 200,
      ),
      cache.acquire(content: content('<p>abc</p>'), width: 210),
      cache.acquire(
        content: content('<p>abc</p>', color: const Color(0xffff0000)),
        width: 200,
      ),
    ];
    expect(cache.layoutBuildCount, 4);
    expect(leases.map((lease) => lease.layout).toSet().length, 4);
    for (final lease in leases) {
      lease.release();
    }
  });

  test(
    'closing the owner retires outstanding leases and prevents late refill',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      final lease = cache.acquire(content: content('<p>abc</p>'), width: 200);
      final layout = lease.layout;
      final fragment = layout.fragment(0, 1);
      cache.close();
      cache.close();
      expect(layout.isDisposed, isTrue);
      expect(lease.isActive, isFalse);
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
      expect(() => lease.layout, throwsStateError);
      expect(() => fragment.sourceAt(Offset.zero), throwsStateError);
      lease.release();
      expect(cache.activeLeases, 0);
      expect(
        () => cache.acquire(content: content('<p>abc</p>'), width: 200),
        throwsStateError,
      );
    },
  );

  test('a warm value cannot bypass current input admission', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final normal = cache.acquire(content: content('<p>abc</p>'), width: 200);
    normal.release();
    expect(
      () => cache.acquire(
        content: content('<p style="text-indent:-2em">abc</p>'),
        width: 200,
      ),
      throwsA(isA<ForumBodyParagraphLayoutException>()),
    );
    expect(cache.entryCount, 1);
    expect(
      () => ForumBodyParagraphCache(maxEntries: 0, maxEstimatedBytes: 1),
      throwsArgumentError,
    );
  });
}

final class _Scaler extends TextScaler {
  const _Scaler(this.large);
  final double large;
  @override
  double scale(double size) => size <= 20 ? size * 2 : size * large;
  @override
  double get textScaleFactor => 2;
}
