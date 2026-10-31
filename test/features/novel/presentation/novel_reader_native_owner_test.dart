import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_owner.dart';

import '../test_support/native_reader_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'layout and mode changes reuse a warm cache until the reading owner closes',
    () {
      final fonts = ChangeNotifier();
      final owner = NovelReaderNativeOwner(fontChanges: fonts);
      addTearDown(() {
        owner.dispose();
        fonts.dispose();
      });
      final first = owner.acquireCache();
      final a = NativeReaderTestFixture('<p>ab</p>', cacheOwner: first.cache);
      expect(first.cache.layoutBuildCount, 1);
      a.session.close();
      first.release();
      first.release();
      expect(first.cache.isClosed, isFalse);
      expect(owner.activeCacheHandles, 0);
      final next = owner.acquireCache();
      expect(next.cache, same(first.cache));
      final b = NativeReaderTestFixture('<p>ab</p>', cacheOwner: next.cache);
      expect(next.cache.layoutBuildCount, 1);
      b.session.close();
      next.release();
      owner.dispose();
      expect(next.cache.isClosed, isTrue);
      expect(owner.estimatedRetainedBytes, 0);
      expect(() => owner.acquireCache(), throwsStateError);
    },
  );

  test('font generations retain only referenced old caches and support reentrant acquisition', () {
    final fonts = ChangeNotifier();
    final owner = NovelReaderNativeOwner(fontChanges: fonts);
    addTearDown(() {
      owner.dispose();
      fonts.dispose();
    });
    final old = owner.acquireCache();
    final fixture = NativeReaderTestFixture('<p>ab</p>', cacheOwner: old.cache);
    final leases = fixture.session.preparePageLeases(0);
    NovelReaderNativeCacheHandle? next;
    owner.addListener(() {
      if (!owner.isClosed) next = owner.acquireCache();
    });
    fonts.notifyListeners();
    expect(old.isCurrent, isFalse);
    expect(old.isActive, isTrue);
    expect(leases.single.isActive, isTrue);
    expect(next!.fontGeneration, 1);
    expect(next!.isCurrent, isTrue);
    expect(next!.cache, isNot(same(old.cache)));
    expect(owner.retainedCacheGenerations, 2);
    expect(owner.estimatedRetainedBytes, greaterThan(0));
    leases.single.release();
    fixture.session.close();
    old.release();
    expect(old.cache.isClosed, isTrue);
    expect(owner.retainedCacheGenerations, 1);
    next!.release();
  });

  test(
    'repeated unreferenced font rotations cannot accumulate old native caches',
    () {
      final fonts = ChangeNotifier();
      final owner = NovelReaderNativeOwner(fontChanges: fonts);
      addTearDown(() {
        owner.dispose();
        fonts.dispose();
      });
      final pinned = owner.acquireCache();
      for (var index = 0; index < 20; index++) {
        fonts.notifyListeners();
        final temporary = owner.acquireCache();
        temporary.release();
        expect(owner.retainedCacheGenerations, 2);
        expect(owner.activeCacheHandles, 1);
      }
      pinned.release();
      expect(pinned.cache.isClosed, isTrue);
      expect(owner.retainedCacheGenerations, 1);
    },
  );

  test('owner closure retires every generation/handle and unbinds font notifications', () {
    final fonts = ChangeNotifier();
    final owner = NovelReaderNativeOwner(fontChanges: fonts);
    final a = owner.acquireCache();
    fonts.notifyListeners();
    final b = owner.acquireCache();
    final fixture = NativeReaderTestFixture('<p>ab</p>', cacheOwner: b.cache);
    final leases = fixture.session.preparePageLeases(0);
    owner.dispose();
    expect(owner.activeCacheHandles, 0);
    expect(owner.retainedCacheGenerations, 0);
    expect(a.isActive, isFalse);
    expect(b.isCurrent, isFalse);
    expect(leases.single.isActive, isFalse);
    final generation = owner.fontGeneration;
    fonts.notifyListeners();
    expect(owner.fontGeneration, generation);
    a.release();
    b.release();
    owner.dispose();
    fonts.dispose();
  });

  testWidgets('a Host can retire its owner during a real font notification', (
    tester,
  ) async {
    final owner = NovelReaderNativeOwner();
    var notifications = 0;
    owner.addListener(() {
      notifications++;
      owner.dispose();
    });
    await PaintingBinding.instance.handleSystemMessage({'type': 'fontsChange'});
    expect(owner.isClosed, isTrue);
    expect(notifications, 1);
    await PaintingBinding.instance.handleSystemMessage({'type': 'fontsChange'});
    expect(notifications, 1);
  });

  testWidgets(
    'actual system font event keeps old Surface alive until new cache handoff',
    (tester) async {
      final owner = NovelReaderNativeOwner();
      addTearDown(owner.dispose);
      final old = owner.acquireCache();
      final a = NativeReaderTestFixture('<p>ab</p>', cacheOwner: old.cache);
      final oldLeases = a.session.preparePageLeases(0);
      Widget page(
        NativeReaderTestFixture fixture,
        List<ForumBodyParagraphLease> leases,
      ) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100,
            height: 100,
            child: ForumBodyTextPageSurface(
              key: ObjectKey(fixture),
              snapshot: fixture.session.snapshot,
              pageIndex: 0,
              layoutId: fixture.session.snapshot.layoutId,
              leases: leases,
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(a, oldLeases));
      await PaintingBinding.instance.handleSystemMessage({
        'type': 'fontsChange',
      });
      await tester.pump();
      expect(old.isCurrent, isFalse);
      expect(oldLeases.single.isActive, isTrue);
      expect(tester.takeException(), isNull);
      final current = owner.acquireCache();
      final b = NativeReaderTestFixture(
        '<p>ab</p>',
        cacheOwner: current.cache,
        layoutId: 'new-font-generation',
      );
      final nextLeases = b.session.preparePageLeases(0);
      expect(current.cache.layoutBuildCount, 1);
      await tester.pumpWidget(page(b, nextLeases));
      expect(oldLeases.single.isActive, isFalse);
      a.session.close();
      old.release();
      expect(old.cache.isClosed, isTrue);
      expect(nextLeases.single.isActive, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      b.session.close();
      current.release();
      owner.dispose();
      expect(nextLeases.single.isActive, isFalse);
      expect(owner.estimatedRetainedBytes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
