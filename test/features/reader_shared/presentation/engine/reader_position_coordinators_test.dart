import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_restore_coordinator.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_seek_coordinator.dart';

void main() {
  test(
    'repeated frames share one active restore and a finished retry can start',
    () {
      final coordinator = ReaderRestoreCoordinator();
      final first = coordinator.begin(isSurfaceCurrent: () => true)!;
      expect(coordinator.begin(isSurfaceCurrent: () => true), isNull);
      coordinator.finish(first);
      final retry = coordinator.begin(isSurfaceCurrent: () => true)!;
      expect(retry.generation, greaterThan(first.generation));
      expect(coordinator.isCurrent(retry), isTrue);
    },
  );

  test('stale restore completion cannot finish the new surface attempt', () {
    final coordinator = ReaderRestoreCoordinator();
    var oldSurfaceCurrent = true;
    final old = coordinator.begin(isSurfaceCurrent: () => oldSurfaceCurrent)!;
    oldSurfaceCurrent = false;
    final next = coordinator.begin(isSurfaceCurrent: () => true)!;
    coordinator.finish(old);
    expect(coordinator.isCurrent(old), isFalse);
    expect(coordinator.isCurrent(next), isTrue);
    expect(coordinator.begin(isSurfaceCurrent: () => true), isNull);
  });

  test('restore invalidation and close reject queued work', () {
    final coordinator = ReaderRestoreCoordinator();
    final old = coordinator.begin(isSurfaceCurrent: () => true)!;
    coordinator.invalidate();
    expect(coordinator.isCurrent(old), isFalse);
    final next = coordinator.begin(isSurfaceCurrent: () => true)!;
    coordinator.close();
    coordinator.finish(old);
    expect(coordinator.isCurrent(next), isFalse);
    expect(coordinator.begin(isSurfaceCurrent: () => true), isNull);
  });

  test(
    'slider throttles commit while preserving the active target and preview',
    () {
      final coordinator = ReaderSeekCoordinator();
      final now = DateTime.utc(2026);
      final first = coordinator.beginSlider(
        targetIndex: 2,
        isSurfaceCurrent: () => true,
        now: now,
      )!;
      coordinator.preview(5);
      expect(
        coordinator.beginSlider(
          targetIndex: 5,
          isSurfaceCurrent: () => true,
          now: now.add(const Duration(milliseconds: 119)),
        ),
        isNull,
      );
      expect(coordinator.pendingIndex, 2);
      expect(coordinator.previewIndex, 5);
      expect(coordinator.isCurrent(first), isTrue);
      expect(coordinator.finish(first), isTrue);
      expect(coordinator.isSliderLocked, isFalse);
      expect(coordinator.previewIndex, isNull);
    },
  );

  test('refresh gives a new lease and old finally cannot unlock it', () {
    final coordinator = ReaderSeekCoordinator();
    final now = DateTime.utc(2026);
    final old = coordinator.beginSlider(
      targetIndex: 2,
      isSurfaceCurrent: () => true,
      now: now,
    )!;
    coordinator.reset();
    final next = coordinator.beginSlider(
      targetIndex: 4,
      isSurfaceCurrent: () => true,
      now: now,
    )!;
    expect(next.generation, greaterThan(old.generation));
    expect(coordinator.finish(old), isFalse);
    expect(coordinator.pendingIndex, 4);
    expect(coordinator.isSliderLocked, isTrue);
    expect(coordinator.isCurrent(next), isTrue);
  });

  test(
    'same-owner refresh clears the lock while retaining commit throttle',
    () {
      final coordinator = ReaderSeekCoordinator();
      final now = DateTime.utc(2026);
      final old = coordinator.beginSlider(
        targetIndex: 2,
        isSurfaceCurrent: () => true,
        now: now,
      )!;
      coordinator.reset(resetThrottle: false);
      expect(coordinator.isSliderLocked, isFalse);
      expect(
        coordinator.beginSlider(
          targetIndex: 4,
          isSurfaceCurrent: () => true,
          now: now.add(const Duration(milliseconds: 119)),
        ),
        isNull,
      );
      final next = coordinator.beginSlider(
        targetIndex: 4,
        isSurfaceCurrent: () => true,
        now: now.add(const Duration(milliseconds: 120)),
      )!;
      expect(coordinator.finish(old), isFalse);
      expect(coordinator.isCurrent(next), isTrue);
    },
  );

  test(
    'a later slider commit supersedes one awaiting its business callback',
    () {
      final coordinator = ReaderSeekCoordinator();
      final now = DateTime.utc(2026);
      final old = coordinator.beginSlider(
        targetIndex: 2,
        isSurfaceCurrent: () => true,
        now: now,
      )!;
      final next = coordinator.beginSlider(
        targetIndex: 3,
        isSurfaceCurrent: () => true,
        now: now.add(const Duration(milliseconds: 120)),
      )!;
      expect(coordinator.isCurrent(old), isFalse);
      expect(coordinator.finish(old), isFalse);
      expect(coordinator.isCurrent(next), isTrue);
    },
  );

  test('mode change invalidates slider work without claiming its UI lock', () {
    final coordinator = ReaderSeekCoordinator();
    final slider = coordinator.beginSlider(
      targetIndex: 2,
      isSurfaceCurrent: () => true,
      now: DateTime.utc(2026),
    )!;
    var modeCurrent = true;
    final mode = coordinator.beginModeChange(
      targetIndex: 2,
      isSurfaceCurrent: () => modeCurrent,
    )!;
    expect(coordinator.isCurrent(slider), isFalse);
    expect(coordinator.isSliderLocked, isFalse);
    expect(coordinator.pendingIndex, isNull);
    expect(coordinator.previewIndex, isNull);
    modeCurrent = false;
    expect(coordinator.isCurrent(mode), isFalse);
  });

  test('closed seeks cannot accept preview or commits', () {
    final coordinator = ReaderSeekCoordinator();
    final active = coordinator.beginSlider(
      targetIndex: 2,
      isSurfaceCurrent: () => true,
      now: DateTime.utc(2026),
    )!;
    coordinator.close();
    coordinator.preview(4);
    expect(coordinator.previewIndex, isNull);
    expect(coordinator.isCurrent(active), isFalse);
    expect(coordinator.finish(active), isFalse);
    expect(
      coordinator.beginModeChange(targetIndex: 2, isSurfaceCurrent: () => true),
      isNull,
    );
  });
}
