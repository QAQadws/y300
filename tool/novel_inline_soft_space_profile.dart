import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

/// Startup coverage for the package font and the real parent cache. Deliberately
/// never calls FontLoader: the newly launched engine must load its own bundle.
/// These geometry/lifetime checks are not frame-time or throughput measurements.
const profileInlineSoftSpaceCaseCount = 14;

List<Map<String, Object>> profileInlineSoftSpaces() {
  final records = <Map<String, Object>>[];
  for (var mode = 0; mode < profileInlineSoftSpaceCaseCount; mode++) {
    final direction = mode.isOdd ? TextDirection.rtl : TextDirection.ltr;
    final large = mode == 4 || mode == 5;
    final fractional = mode == 6 || mode == 7 || mode >= 12;
    final justified = mode == 8 || mode == 9;
    final wraps = large || mode == 2 || mode == 3;
    final gap = mode >= 12
        ? 12.571334838867188
        : mode >= 10
        ? 9.90234375
        : large
        ? 1000.0
        : (fractional ? 10.375 : 10.0);
    final width = mode >= 10
        ? 40 + gap
        : large
        ? 20.0
        : mode == 2 || mode == 3
        ? 49.0
        : justified
        ? 60.0
        : fractional
        ? 50.375
        : 50.0;
    final document = const ForumBodyParser().parse(
      html:
          '<p dir="${direction.name}" '
          'style="text-align:${justified ? 'justify' : 'start'}">'
          'A B${justified ? ' C' : ''}</p>',
      sourceId: 'profile-bundled-soft-space-$mode',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(
      document,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(fontSize: 20, height: 1),
        fontRevision: 'profile-system20',
        linkColor: const Color(0xff0000ff),
      ),
    );
    final text = const ForumBodyParagraphContentBuilder().build(
      document: document,
      styles: styles,
      path: '0',
    );
    final content = ForumBodyInlineSpanContent.compose(
      identity: document.identity,
      path: '0',
      fontRevision: styles.fontRevision,
      styleRevision: styles.resolverRevision,
      style: text.style,
      contexts: [text],
      atomicRanges: [
        for (var i = 0; i < 3; i++) (startUtf16: i, endUtf16: i + 1),
      ],
      softSpaceAtoms: {1},
    );
    final dimensions = [
      for (var i = 0; i < 3; i++)
        PlaceholderDimensions(
          size: Size(i == 1 ? gap : 20, i == 1 && large ? 1000 : 30),
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          baselineOffset: i == 1 && large ? 500 : 26,
        ),
    ];
    final scaler = fractional
        ? const TextScaler.linear(1.27)
        : TextScaler.noScaling;
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    Map<String, Object>? record;
    try {
      final lease = cache.acquireInline(
        content: content,
        width: width,
        dimensions: dimensions,
        textScaler: scaler,
      );
      try {
        final layout = lease.layout;
        final expectedRows = wraps || justified ? 2 : 1;
        if (layout.isAtomTrimmed(1) != wraps ||
            layout.lines.length != expectedRows ||
            layout.selection(1, 2).atoms.length != (wraps ? 0 : 1)) {
          throw StateError(
            'Bundled soft-space row/trim coverage failed: mode=$mode '
            'rows=${layout.lines.length} height=${layout.height} '
            'trimmed=${layout.isAtomTrimmed(1)} '
            'selection=${layout.selection(1, 2).atoms.length}',
          );
        }
        // Native system-font row rounding differs across hosts. A huge trimmed
        // gap must have exactly the height of the same two real wrapped atoms.
        if (large && layout.height != records[mode - 2]['height']) {
          throw StateError('Trimmed soft-space expanded the physical frame');
        }
        if (!wraps &&
            (layout.atomBoxes[1].right - layout.atomBoxes[1].left - gap).abs() >
                .001) {
          throw StateError('Bundled soft-space advance failed');
        }
        final builds = cache.layoutBuildCount;
        if (builds != 1) {
          throw StateError('Bundled soft-space cold shape count failed');
        }
        record = {
          'event': 'inline_soft_space',
          'mode': mode,
          'direction': direction.name,
          'width': width,
          'gap': gap,
          'rows': layout.lines.length,
          'height': layout.height,
          'trimmed': layout.isAtomTrimmed(1),
          'frameBytes': layout.fragmentFrameBytes,
          'coldBuilds': builds,
        };
        // Match actual retention: release the cold pin before a warm lookup.
        lease.release();
        final warm = cache.tryAcquireInlineCached(
          content: content,
          width: width,
          dimensions: dimensions,
          textScaler: scaler,
        );
        if (warm == null) {
          throw StateError('Bundled soft-space warm lookup missed');
        }
        try {
          if (!identical(warm.layout, layout) ||
              cache.layoutBuildCount != builds) {
            throw StateError('Bundled soft-space warm geometry rebuilt');
          }
          record['warmBuilds'] = cache.layoutBuildCount - builds;
        } finally {
          warm.release();
        }
      } finally {
        lease.release();
      }
    } finally {
      cache.close();
    }
    if (cache.activeLeases != 0 || cache.estimatedRetainedBytes != 0) {
      throw StateError('Bundled soft-space owner was retained');
    }
    record.addAll({
      'exitPins': cache.activeLeases,
      'exitBytes': cache.estimatedRetainedBytes,
      'passed': true,
    });
    records.add(record);
  }
  return List.unmodifiable(records.map(Map<String, Object>.unmodifiable));
}
