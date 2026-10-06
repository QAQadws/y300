import 'package:characters/characters.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_conversion_position.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_background_work.dart';

/// Projects a visible DOM position through a conversion of the same source.
/// Text identities remain checked on both sides; no old layout/page is reused.
/// The result is a display hint and must remain read-only until user navigation.
final class NovelReaderConversionRestoreService {
  const NovelReaderConversionRestoreService();

  Future<NovelReaderTextAnchor?> projectInBackground({
    required NovelReaderConversionPosition source,
    required String rawHtml,
    required String conversionIdentity,
    required NovelReaderPreparedChapter target,
  }) => NovelReaderBackgroundWork.run(
    codeUnits: source.chapter.html.length + target.html.length,
    transform: () => project(
      source: source,
      rawHtml: rawHtml,
      conversionIdentity: conversionIdentity,
      target: target,
    ),
  );

  NovelReaderTextAnchor? project({
    required NovelReaderConversionPosition source,
    required String rawHtml,
    required String conversionIdentity,
    required NovelReaderPreparedChapter target,
  }) {
    final anchor = source.anchor;
    final before = source.chapter.flowUnits;
    final after = target.flowUnits;
    if (rawHtml.isEmpty ||
        source.rawHtml != rawHtml ||
        source.conversionIdentity == conversionIdentity ||
        source.chapter.episodeId != target.episodeId ||
        anchor.episodeId != target.episodeId ||
        !anchor.hasCanonicalTextOffset ||
        before.length != after.length ||
        source.chapter.legacyMarkupNormalization.revision !=
            target.legacyMarkupNormalization.revision) {
      return null;
    }

    // Prefer the unit beginning at a shared boundary, rather than the end of
    // its predecessor. Repeated text is distinguished by its actual DOM unit.
    final candidates = <int>[];
    for (var i = 0; i < before.length; i++) {
      final unit = before[i];
      if (unit.sourceAnchorProjection == null ||
          unit.startAnchor.nodeId != anchor.nodeId ||
          unit.startAnchor.textIdentity != anchor.textIdentity ||
          unit.startAnchor.formatVersion != anchor.formatVersion) {
        continue;
      }
      if (anchor.textOffset >= unit.startAnchor.textOffset &&
          (anchor.textOffset < unit.endAnchor.textOffset ||
              anchor.textOffset == unit.startAnchor.textOffset)) {
        candidates.add(i);
      }
    }
    if (candidates.isEmpty) {
      for (var i = 0; i < before.length; i++) {
        final unit = before[i];
        if (unit.sourceAnchorProjection != null &&
            unit.endAnchor.nodeId == anchor.nodeId &&
            unit.endAnchor.textIdentity == anchor.textIdentity &&
            unit.endAnchor.formatVersion == anchor.formatVersion &&
            unit.endAnchor.textOffset == anchor.textOffset) {
          candidates.add(i);
        }
      }
    }
    if (candidates.length != 1) return null;
    final index = candidates.single;
    final sourceProjection = before[index].sourceAnchorProjection!;
    final targetProjection = after[index].sourceAnchorProjection;
    if (targetProjection == null ||
        !targetProjection.baseAnchor.hasCanonicalTextOffset) {
      return null;
    }
    final sourceOffset = sourceProjection.semanticOffsetsBySourceRuneBoundary
        .indexOf(anchor.textOffset);
    if (sourceOffset < 0) return null;

    List<(String, String)>? selectedTexts;
    for (var i = 0; i < before.length; i++) {
      final texts = <(String, String)>[];
      if (!_pairNodes(
        html_parser.parseFragment(before[i].html),
        html_parser.parseFragment(after[i].html),
        texts,
      )) {
        return null;
      }
      if (i == index) selectedTexts = texts;
    }
    final texts = selectedTexts!;
    if (texts.fold<int>(0, (n, pair) => n + pair.$1.runes.length) !=
            sourceProjection.sourceRuneLength ||
        texts.fold<int>(0, (n, pair) => n + pair.$2.runes.length) !=
            targetProjection.sourceRuneLength) {
      return null;
    }
    var oldCursor = 0;
    var newCursor = 0;
    for (final (oldText, newText) in texts) {
      final oldLength = oldText.runes.length;
      if (sourceOffset <= oldCursor + oldLength) {
        return targetProjection.anchorAtSourceRune(
          newCursor +
              _projectTextBoundary(oldText, newText, sourceOffset - oldCursor),
        );
      }
      oldCursor += oldLength;
      newCursor += newText.runes.length;
    }
    return targetProjection.anchorAtSourceRune(newCursor);
  }

  bool _pairNodes(dom.Node left, dom.Node right, List<(String, String)> texts) {
    if (left is dom.Text && right is dom.Text) {
      texts.add((left.data, right.data));
      return true;
    }
    if (left.runtimeType != right.runtimeType) return false;
    if (left is dom.Element && right is dom.Element) {
      if (left.localName != right.localName ||
          left.attributes.length != right.attributes.length ||
          left.attributes.entries.any(
            (e) => right.attributes[e.key] != e.value,
          )) {
        return false;
      }
      if (left.localName == 'script' || left.localName == 'style') return true;
      if (left.localName == 'br') {
        texts.add(('\n', '\n'));
        return true;
      }
    }
    if (left.nodes.length != right.nodes.length) return false;
    for (var i = 0; i < left.nodes.length; i++) {
      if (!_pairNodes(left.nodes[i], right.nodes[i], texts)) return false;
    }
    return true;
  }

  int _projectTextBoundary(String source, String target, int runeOffset) {
    final oldClusters = source.characters.toList(growable: false);
    final newClusters = target.characters.toList(growable: false);
    var oldBoundary = 0;
    var clusterIndex = 0;
    while (clusterIndex < oldClusters.length &&
        oldBoundary + oldClusters[clusterIndex].runes.length <= runeOffset) {
      oldBoundary += oldClusters[clusterIndex].runes.length;
      clusterIndex++;
    }
    int targetBoundary(int index) => newClusters
        .take(index)
        .fold<int>(0, (length, cluster) => length + cluster.runes.length);
    // Conversion preserves text-node order. Equal grapheme counts give a
    // local ordinal display projection, without assuming equal glyph widths.
    if (oldClusters.length == newClusters.length) {
      return targetBoundary(clusterIndex);
    }
    var prefix = 0;
    while (prefix < oldClusters.length &&
        prefix < newClusters.length &&
        oldClusters[prefix] == newClusters[prefix]) {
      prefix++;
    }
    if (clusterIndex <= prefix) return targetBoundary(clusterIndex);
    var suffix = 0;
    while (suffix < oldClusters.length - prefix &&
        suffix < newClusters.length - prefix &&
        oldClusters[oldClusters.length - suffix - 1] ==
            newClusters[newClusters.length - suffix - 1]) {
      suffix++;
    }
    if (clusterIndex >= oldClusters.length - suffix) {
      return targetBoundary(
        newClusters.length - (oldClusters.length - clusterIndex),
      );
    }
    // A length-changing replacement has no proven interior correspondence.
    // Keep its beginning readable instead of inventing a canonical offset.
    return targetBoundary(prefix);
  }
}
