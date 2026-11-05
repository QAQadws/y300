import 'dart:ui' show Offset, Rect;

import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../domain/models/novel_reader_marks.dart';
import '../models/novel_reader_native_anchor_map.dart';
import '../models/novel_reader_native_page_coverage.dart';
import 'novel_reader_native_page_coverage_cursor.dart';
import 'novel_reader_native_page_hint_search.dart';
import 'novel_reader_native_work_scheduler.dart';
import 'novel_reader_pagination_cancellation.dart';

typedef NovelReaderNativeFlowPoint = ({
  int slice,
  NovelReaderTextAnchor anchor,
  Rect bounds,
  bool isImage,
});

const _scheduler = NovelReaderNativeWorkScheduler();

/// Read the first eligible visible source, or verify one in its new slice.
/// The caller supplies the readable clip in body coordinates.
Future<NovelReaderNativeFlowPoint?> sampleNovelReaderFlowSource({
  required ForumBodyFlowTextWindow window,
  required NovelReaderNativeAnchorMap anchors,
  required Rect readable,
  required NovelReaderPaginationCancellationToken token,
  NovelReaderTextAnchor? preferred,
  int? targetSlice,
  bool includeRenderedImages = false,
}) async {
  final visible = window.bounds.intersect(readable);
  if (visible.isEmpty) return null;
  final snapshot = window.snapshot;
  for (final slice in window.slices) {
    if (!window.isCurrent) return null;
    if (targetSlice != null && targetSlice != slice.index) continue;
    final clip = visible
        .intersect(
          Rect.fromLTWH(
            0,
            slice.top,
            snapshot.width,
            snapshot[slice.index].usedHeight,
          ),
        )
        .shift(Offset(0, -slice.top));
    if (clip.isEmpty) continue;
    final point = await _locate(
      snapshot,
      slice.index,
      slice.fragments,
      anchors,
      clip,
      preferred,
      token,
      isCurrent: () => window.isCurrent,
      includeRenderedImages: includeRenderedImages,
    );
    if (point != null && window.isCurrent) return point;
  }
  return null;
}

/// A source hint only admits a candidate. Prepare its actual layout to find
/// new geometry, then release the temporary delivery before mounting.
Future<NovelReaderNativeFlowPoint?> probeNovelReaderFlowSource({
  required ForumBodyTextPageSession session,
  required ForumBodyTextPageSnapshot prefix,
  required NovelReaderNativeAnchorMap anchors,
  required NovelReaderTextAnchor target,
  required int start,
  required NovelReaderPaginationCancellationToken token,
}) async {
  if (start == prefix.length) return null;
  final search = NovelReaderNativePageHintSearch(
    snapshot: prefix,
    layoutId: prefix.layoutId,
    anchors: anchors,
    anchor: target,
    startPageIndex: start,
  );
  try {
    while (!search.isComplete) {
      token.throwIfCancelled();
      search.advance(maxPages: 8, maxFragments: 64);
      for (final hint in search.takeCandidates()) {
        final index = hint.pageIndex;
        final page = prefix[index];
        if (page.table != null || page.usedHeight <= 0) continue;
        await _scheduler.nextFrame(token);
        final job = session.openPagePreparation(index);
        var fragments = const <ForumBodyPreparedTextFragment>[];
        try {
          while (!job.isReady) {
            final revision = session.layoutBudgetRevision;
            final step = job.advance(maxFragments: 2, maxParts: 8);
            if (step.waitingForLayoutBudget) {
              await _scheduler.waitForLayoutBudget(
                session: session,
                afterRevision: revision,
                token: token,
              );
            }
            if (!step.isReady) await _scheduler.nextFrame(token);
          }
          fragments = job.takeFragments();
          final point = await _locate(
            prefix,
            index,
            fragments,
            anchors,
            Rect.fromLTWH(0, 0, prefix.width, page.usedHeight),
            target,
            token,
          );
          if (point != null) return point;
        } finally {
          for (final fragment in fragments) {
            fragment.close();
          }
          job.close();
        }
      }
      if (!search.isComplete) await _scheduler.nextFrame(token);
    }
    return null;
  } finally {
    search.close();
  }
}

Future<NovelReaderNativeFlowPoint?> _locate(
  ForumBodyTextPageSnapshot snapshot,
  int index,
  List<ForumBodyPreparedTextFragment> fragments,
  NovelReaderNativeAnchorMap anchors,
  Rect clip,
  NovelReaderTextAnchor? preferred,
  NovelReaderPaginationCancellationToken token, {
  bool Function()? isCurrent,
  bool includeRenderedImages = false,
}) async {
  token.throwIfCancelled();
  NovelReaderNativePageCoverageCursor? cursor;
  try {
    final work = cursor = NovelReaderNativePageCoverageCursor.prepared(
      anchors: anchors,
      snapshot: snapshot,
      pageIndex: index,
      layoutId: snapshot.layoutId,
      fragments: fragments,
      viewportClip: clip,
      continuous: true,
    );
    final clock = Stopwatch()..start();
    var steps = 0;
    while (work.state == NovelReaderNativeCoverageState.active) {
      if (steps >= 8 || clock.elapsedMicroseconds >= 3000) {
        await _scheduler.nextFrame(token);
        if (isCurrent?.call() == false) return null;
        clock.reset();
        steps = 0;
      }
      work.advance(maxGraphemes: 64, maxFragments: 4, maxResources: 16);
      steps++;
    }
    final coverage = work.result;
    final location = preferred == null
        ? coverage.locations
              .where(
                (location) => switch (location) {
                  NovelReaderNativeCoveragePoint(:final fragmentBounds) =>
                    fragmentBounds?.isEmpty == false,
                  NovelReaderNativeImageCoverage() =>
                    includeRenderedImages &&
                        location.isRenderedBy(
                          fragments[location.fragmentIndex],
                        ),
                },
              )
              .firstOrNull
        : coverage.locate(preferred);
    if (location == null) return null;
    final bounds = switch (location) {
      NovelReaderNativeCoveragePoint(:final fragmentBounds) => fragmentBounds,
      NovelReaderNativeImageCoverage(:final rect) => rect,
    };
    if (bounds == null || bounds.isEmpty) return null;
    final fragment = snapshot[index].fragments[location.fragmentIndex];
    return (
      slice: index,
      anchor: location.anchor,
      bounds: bounds.shift(Offset(fragment.left, fragment.top)),
      isImage: location is NovelReaderNativeImageCoverage,
    );
  } on NovelReaderNativeCoverageException catch (error) {
    if (error.failure != NovelReaderNativeCoverageFailure.budget) rethrow;
    return null;
  } finally {
    cursor?.close();
  }
}
