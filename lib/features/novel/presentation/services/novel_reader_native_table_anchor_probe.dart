import 'dart:ui' show Offset, Rect;

import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

import '../models/novel_reader_native_anchor_map.dart';
import '../models/novel_reader_native_page_coverage.dart';
import 'novel_reader_native_page_coverage_cursor.dart';
import 'novel_reader_native_work_scheduler.dart';
import 'novel_reader_pagination_cancellation.dart';

typedef NovelReaderNativeTableAnchor = ({
  NovelReaderTextAnchor anchor,
  Rect bounds,
});

/// Reacquire only source-matching cell slices to find geometry in a new
/// layout. This plans a reveal; the mounted table must prove visibility.
Future<NovelReaderNativeTableAnchor?> probeNovelReaderNativeTableAnchor({
  required ForumBodyTextPageSession session,
  required NovelReaderNativeAnchorMap anchors,
  required int pageIndex,
  String? tablePath,
  required NovelReaderTextAnchor target,
  required bool allowNodeCompatibility,
  required NovelReaderNativeWorkScheduler scheduler,
  required NovelReaderPaginationCancellationToken token,
}) async {
  token.throwIfCancelled();
  final table = session.tableLayoutForPage(pageIndex, path: tablePath);
  if (table == null) return null;
  final page = session.snapshot[pageIndex];
  final viewport = tablePath == null
      ? page.table!.bounds
      : page.tableFrames.firstWhere((frame) => frame.path == tablePath).bounds;
  final ranges = anchors
      .sourceCandidates(target, allowNodeCompatibility: allowNodeCompatibility)
      .toList(growable: false);
  final paths = anchors
      .imageCandidatePaths(
        target,
        allowNodeCompatibility: allowNodeCompatibility,
      )
      .toSet();
  final allowNode =
      allowNodeCompatibility && !anchors.hasVerifiedTextIdentity(target);
  var scanned = 0;
  for (final area in table.captions.followedBy(table.cells)) {
    if (++scanned % 32 == 0) await scheduler.nextFrame(token);
    final source = area.element.source;
    if (!_intersects(ranges, source.runeStart, source.runeEnd) &&
        !paths.any((path) => path.startsWith('${area.element.path}/'))) {
      continue;
    }
    final snapshot = area.snapshot;
    for (final page in snapshot) {
      if (++scanned % 32 == 0) await scheduler.nextFrame(token);
      if (!page.fragments.any((fragment) {
        final hint = fragment.sourceHint;
        return fragment.imagePaths.any(paths.contains) ||
            (hint != null && _intersects(ranges, hint.runeStart, hint.runeEnd));
      })) {
        continue;
      }
      final candidate = await _inspectSlice(
        session,
        area,
        page,
        anchors,
        target,
        allowNode,
        viewport,
        scheduler,
        token,
      );
      if (candidate != null) return candidate;
    }
  }
  return null;
}

bool _intersects(
  List<NovelReaderNativeSourceCandidate> ranges,
  int start,
  int end,
) {
  var low = 0, high = ranges.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (ranges[middle].runeEnd < start) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low < ranges.length && ranges[low].runeStart <= end;
}

Future<NovelReaderNativeTableAnchor?> _inspectSlice(
  ForumBodyTextPageSession session,
  ForumBodyTableAreaLayout area,
  ForumBodyTextPage page,
  NovelReaderNativeAnchorMap anchors,
  NovelReaderTextAnchor target,
  bool allowNode,
  Rect viewport,
  NovelReaderNativeWorkScheduler scheduler,
  NovelReaderPaginationCancellationToken token,
) async {
  await scheduler.nextFrame(token);
  final snapshot = area.snapshot;
  final job = area.openPagePreparation(page.index);
  var fragments = const <ForumBodyPreparedTextFragment>[];
  NovelReaderNativePageCoverageCursor? cursor;
  try {
    while (!job.isReady) {
      final revision = session.layoutBudgetRevision;
      final step = job.advance(maxFragments: 2, maxParts: 8);
      if (step.waitingForLayoutBudget) {
        await scheduler.waitForLayoutBudget(
          session: session,
          afterRevision: revision,
          token: token,
        );
      }
      if (!step.isReady) await scheduler.nextFrame(token);
    }
    fragments = job.takeFragments();
    final work = cursor = NovelReaderNativePageCoverageCursor.prepared(
      anchors: anchors,
      snapshot: snapshot,
      pageIndex: page.index,
      layoutId: snapshot.layoutId,
      fragments: fragments,
      viewportClip: Rect.fromLTWH(0, 0, snapshot.width, page.usedHeight),
    );
    final clock = Stopwatch()..start();
    var steps = 0;
    while (work.state == NovelReaderNativeCoverageState.active) {
      work.advance(maxGraphemes: 64, maxFragments: 4, maxResources: 16);
      if (work.state == NovelReaderNativeCoverageState.active &&
          (++steps >= 8 || clock.elapsedMicroseconds >= 3000)) {
        await scheduler.nextFrame(token);
        clock.reset();
        steps = 0;
      }
    }
    final coverage = work.result;
    final location =
        coverage.locate(target) ??
        (allowNode
            ? coverage.locations
                  .where((point) => point.anchor.nodeId == target.nodeId)
                  .firstOrNull
            : null);
    final local = switch (location) {
      NovelReaderNativeCoveragePoint(:final fragmentBounds) => fragmentBounds,
      NovelReaderNativeImageCoverage(:final rect) => rect,
      null => null,
    };
    if (location == null ||
        local == null ||
        local.width > viewport.width ||
        local.height > viewport.height) {
      return null;
    }
    final fragment = page.fragments[location.fragmentIndex];
    return (
      anchor: location.anchor,
      bounds: local.shift(
        area.contentBounds.topLeft +
            Offset(fragment.left, area.pageTop(page.index) + fragment.top),
      ),
    );
  } on NovelReaderNativeCoverageException catch (error) {
    if (error.failure != NovelReaderNativeCoverageFailure.budget) rethrow;
    return null;
  } finally {
    cursor?.close();
    for (final fragment in fragments) {
      fragment.close();
    }
    job.close();
  }
}
