import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

import '../models/novel_reader_native_anchor_map.dart';
import 'novel_reader_native_page_coverage_cursor.dart';
import 'novel_reader_native_work_scheduler.dart';
import 'novel_reader_pagination_cancellation.dart';

/// Reading evidence borrowed from one exact mounted, settled table window.
/// Results drop individual glyph points and become invalid when it moves.
final class NovelReaderNativeTableWindowProof {
  const NovelReaderNativeTableWindowProof._(
    this.window,
    this.anchor,
    this.matchesPreferred,
  );

  final ForumBodyTableVisibleWindow window;
  final NovelReaderTextAnchor? anchor;
  final bool matchesPreferred;
  bool get isCurrent => window.isCurrent;

  static Future<NovelReaderNativeTableWindowProof?> prepare({
    required ForumBodyTableVisibleWindow window,
    required NovelReaderNativeAnchorMap anchors,
    required NovelReaderNativeWorkScheduler scheduler,
    required NovelReaderPaginationCancellationToken token,
    NovelReaderTextAnchor? preferred,
  }) async {
    await scheduler.nextFrame(token);
    final clock = Stopwatch()..start();
    var steps = 0;
    NovelReaderTextAnchor? first;
    for (final slice in window.slices) {
      if (!window.isCurrent) return null;
      final snapshot = slice.area.snapshot;
      final clip = window.bounds.intersect(slice.bounds);
      if (clip.isEmpty) continue;
      NovelReaderNativePageCoverageCursor? cursor;
      try {
        final work = cursor = NovelReaderNativePageCoverageCursor.prepared(
          anchors: anchors,
          snapshot: snapshot,
          pageIndex: slice.page,
          layoutId: snapshot.layoutId,
          fragments: slice.fragments,
          viewportClip: clip.shift(-slice.bounds.topLeft),
        );
        while (work.state == NovelReaderNativeCoverageState.active) {
          if (steps >= 8 || clock.elapsedMicroseconds >= 3000) {
            await scheduler.nextFrame(token);
            if (!window.isCurrent) return null;
            clock.reset();
            steps = 0;
          }
          work.advance(maxGraphemes: 64, maxFragments: 4, maxResources: 16);
          steps++;
        }
        final coverage = work.result;
        first ??= coverage.locations.firstOrNull?.anchor;
        if (preferred == null && first != null) break;
        final exact = preferred == null ? null : coverage.locate(preferred);
        if (exact != null) {
          return window.isCurrent
              ? NovelReaderNativeTableWindowProof._(window, exact.anchor, true)
              : null;
        }
      } on NovelReaderNativeCoverageException catch (error) {
        if (error.failure != NovelReaderNativeCoverageFailure.budget) rethrow;
        // A slice that exhausts its inspection limit provides no partial proof.
        // Earlier completed slices remain valid in the same physical window.
      } finally {
        cursor?.close();
      }
    }
    return window.isCurrent
        ? NovelReaderNativeTableWindowProof._(window, first, false)
        : null;
  }
}
