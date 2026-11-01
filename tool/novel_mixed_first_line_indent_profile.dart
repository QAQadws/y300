import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const profileMixedFirstLineIndentCaseCount = 4;

/// Real typed page preparation outside timing windows. No FontLoader or second
/// renderer: the actual production session must consume the bundled font ABI.
List<Map<String, Object>> profileMixedFirstLineIndents({
  void Function(Map<String, Object>)? onFailure,
}) {
  final records = <Map<String, Object>>[];
  for (final direction in TextDirection.values) {
    for (final advance in [20.0, 12.571334838867188]) {
      const width = 80.0;
      // Android's actual system-font ruby frame is about35.16px at20px text;
      // keep one whole row per page without relying on Tester font metrics.
      const height = 40.0;
      final document = const ForumBodyParser().parse(
        html:
            '<p dir="${direction.name}" style="text-indent:${advance}px">'
            '<ruby>AA<rt>xx</rt></ruby> <ruby>B<rt>y</rt></ruby> '
            '<ruby>C<rt>z</rt></ruby><br><ruby>D<rt>u</rt></ruby> '
            '<ruby>E<rt>v</rt></ruby> <ruby>F<rt>w</rt></ruby></p>',
        sourceId: 'profile-mixed-indent',
        conversionIdentity: 'none',
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 32,
        maxEstimatedBytes: 1 << 22,
      );
      final session = ForumBodyTextPageSession(
        document: document,
        reader: ForumBodyReaderStyle(
          textStyle: const TextStyle(fontSize: 20, height: 1),
          fontRevision: 'profile-system20',
          linkColor: const Color(0xff0000ff),
          paragraphAfter: 0,
        ),
        cache: cache,
        limits: const ForumBodyTextPageSessionLimits(
          maxPages: 128,
          maxFragments: 512,
          maxParagraphs: 128,
          maxTextCodeUnits: 16384,
          maxRuns: 1024,
          maxIssuedLeases: 64,
        ),
        layoutId: 'profile-mixed-indent',
        width: width,
        height: height,
      );
      late Map<String, Object> record;
      try {
        for (var work = 0; !session.isComplete; work++) {
          if (work >= 10000) throw StateError('Mixed indent source stalled');
          session.advance(maxEvents: 32, maxLines: 8);
        }
        var glyphs = 0;
        var sawContinuation = false;
        double? firstAdvance;
        for (var page = 0; page < session.snapshot.length; page++) {
          final fragments = _prepare(session, page);
          try {
            validateForumBodyPreparedTextPageBinding(
              snapshot: session.snapshot,
              pageIndex: page,
              layoutId: 'profile-mixed-indent',
              fragments: fragments,
            );
            for (final prepared
                in fragments.cast<ForumBodyPreparedInlineFragment>()) {
              final parent =
                  prepared.nativeLeases.first as ForumBodyInlineParagraphLease;
              final layout = parent.layout;
              final owns = prepared.view.content.appliesFirstLineIndent;
              if (layout.projection.enginePrefix.length != (owns ? 2 : 0)) {
                throw StateError(
                  'Mixed indent lost formatting-context ownership',
                );
              }
              if (!owns) sawContinuation = true;
              if (page == 0 && firstAdvance == null) {
                final row = layout.lines.first;
                final boxes = [
                  for (final atom in layout.projection.atoms)
                    if (!atom.isSoftSpace &&
                        !layout.isAtomTrimmed(atom.index) &&
                        atom.engineUtf16 >= row.engineCoverageStartUtf16 &&
                        atom.engineUtf16 < row.engineCoverageEndUtf16)
                      layout.atomBoxes[atom.index],
                ];
                firstAdvance = direction == TextDirection.ltr
                    ? boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b)
                    : width -
                          boxes
                              .map((b) => b.right)
                              .reduce((a, b) => a > b ? a : b);
                if ((firstAdvance - advance).abs() > .001) {
                  throw StateError('Mixed native first-line advance differs');
                }
              }
              final text = prepared.projection.text;
              for (var i = 0; i < text.length; i++) {
                if ('ABCDEF'.contains(text[i]) &&
                    prepared.glyphBoxes(i, i + 1).isNotEmpty) {
                  glyphs++;
                }
              }
            }
          } finally {
            for (final fragment in fragments) {
              fragment.close();
            }
          }
          if (cache.activeLeases != 0 || session.activeIssuedLeases != 0) {
            throw StateError('Mixed indent page retained visible owners');
          }
        }
        if (glyphs != 7 || !sawContinuation || firstAdvance == null) {
          throw StateError('Mixed indent lost real glyphs or BR continuation');
        }
        final builds = cache.layoutBuildCount;
        final pictures = cache.pictureBuildCount;
        final warm = _prepare(session, 0);
        for (final fragment in warm) {
          fragment.close();
        }
        if (cache.layoutBuildCount != builds ||
            cache.pictureBuildCount != pictures) {
          throw StateError('Mixed indent warm page reshaped or recorded');
        }
        record = {
          'event': 'mixed_first_line_indent',
          'direction': direction.name,
          'advance': advance,
          'actualFirst': firstAdvance,
          'pages': session.snapshot.length,
          'baseGlyphs': glyphs,
          'brContinuation': sawContinuation,
          'warmBuilds': 0,
          'warmPictures': 0,
        };
      } on ForumBodyTextPageException catch (error) {
        onFailure?.call({
          'event': 'mixed_indent_failure',
          'reason': error.failure.name,
          'direction': direction.name,
          'advance': advance,
          'height': height,
          'sourceComplete': session.isComplete,
          'pages': session.snapshot.length,
        });
        rethrow;
      } finally {
        session.close();
        cache.close();
      }
      if (cache.activeLeases != 0 || cache.estimatedRetainedBytes != 0) {
        throw StateError('Mixed indent retained its native owner');
      }
      record.addAll({'exitPins': 0, 'exitBytes': 0, 'passed': true});
      records.add(Map.unmodifiable(record));
    }
  }
  return List.unmodifiable(records);
}

List<ForumBodyPreparedTextFragment> _prepare(
  ForumBodyTextPageSession session,
  int page,
) {
  final job = session.openPagePreparation(page);
  try {
    for (var work = 0; !job.isReady; work++) {
      if (work >= 10000) {
        throw StateError('Mixed indent page preparation stalled');
      }
      job.advance(maxFragments: 1, maxParts: 8);
    }
    return job.takeFragments();
  } finally {
    job.close();
  }
}
