import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_source_provenance.dart';
import 'package:y300/features/novel/domain/models/novel_rich_block_text.dart';
import 'package:y300/features/novel/domain/services/novel_reader_text_normalization.dart';

import '../models/novel_reader_native_anchor_map.dart';
import '../models/novel_reader_source_anchor_projection.dart';

enum NovelReaderNativeAnchorBindingFailure {
  identity,
  conversion,
  provenance,
  origin,
  budget,
}

final class NovelReaderNativeAnchorBindingException implements Exception {
  const NovelReaderNativeAnchorBindingException(this.failure);
  final NovelReaderNativeAnchorBindingFailure failure;
  @override
  String toString() =>
      'NovelReaderNativeAnchorBindingException(${failure.name})';
}

final class NovelReaderNativeAnchorBindingLimits {
  const NovelReaderNativeAnchorBindingLimits({
    this.origins = const NovelReaderSourceProvenanceLimits(),
    this.maxSourceBoundaries = 1024 * 1024,
    this.maxSemanticCodeUnits = 512 * 1024,
  });
  final NovelReaderSourceProvenanceLimits origins;
  final int maxSourceBoundaries;
  final int maxSemanticCodeUnits;
}

/// Data-only binding for the exact parse input and actual conversion. May run
/// in the preparation worker. No HTML reparsing or text-based node discovery.
final class NovelReaderNativeAnchorBinder {
  const NovelReaderNativeAnchorBinder({
    this.limits = const NovelReaderNativeAnchorBindingLimits(),
  });
  final NovelReaderNativeAnchorBindingLimits limits;

  NovelReaderNativeAnchorMap bind({
    required String episodeId,
    required String sourceId,
    required NovelReaderDocument semanticDocument,
    required ForumBodyDocument bodyDocument,
  }) {
    final budget = _BindingBudget(limits);
    if (semanticDocument.episodeId != episodeId ||
        bodyDocument.identity.sourceId != sourceId ||
        bodyDocument.identity.parserRevision != ForumBodyParser.revision) {
      _fail(NovelReaderNativeAnchorBindingFailure.identity);
    }
    if (semanticDocument.textConversionIdentity == null ||
        semanticDocument.textConversionIdentity !=
            bodyDocument.identity.conversionIdentity) {
      _fail(NovelReaderNativeAnchorBindingFailure.conversion);
    }
    final provenance = semanticDocument.sourceProvenance;
    if (provenance == null) {
      _fail(NovelReaderNativeAnchorBindingFailure.provenance);
    }
    if (provenance.inputHash != bodyDocument.identity.inputHash) {
      _fail(NovelReaderNativeAnchorBindingFailure.identity);
    }
    budget.admitOrigins(provenance.origins);
    final segments = <NovelReaderNativeAnchorSegment>[];
    final unmapped = <String>[];
    _SemanticTarget? target;
    var previousTargetIndex = -1;
    var semanticStart = 0;
    var sourceEnd = 0;
    for (final origin in provenance.origins) {
      final node = bodyDocument.nodeAtPath(origin.path);
      if (origin.text.isEmpty ||
          node == null ||
          node.source.runeStart < sourceEnd ||
          node.source.runeEnd < node.source.runeStart ||
          node.source.runeEnd > bodyDocument.sourceMap.runeLength) {
        _fail(NovelReaderNativeAnchorBindingFailure.origin);
      }
      sourceEnd = node.source.runeEnd;
      if (target?.nodeId != origin.nodeId) {
        if (target != null && semanticStart != target.runes.length) {
          _fail(NovelReaderNativeAnchorBindingFailure.origin);
        }
        target = _SemanticTarget.read(semanticDocument, origin.nodeId, budget);
        if (target.index <= previousTargetIndex) {
          _fail(NovelReaderNativeAnchorBindingFailure.origin);
        }
        previousTargetIndex = target.index;
        semanticStart = 0;
      }
      if (origin.semanticCodePointStart != semanticStart) {
        _fail(NovelReaderNativeAnchorBindingFailure.origin);
      }
      for (final rune in origin.text.runes) {
        if (semanticStart >= target!.runes.length ||
            rune != target.runes[semanticStart++]) {
          _fail(NovelReaderNativeAnchorBindingFailure.origin);
        }
      }
      // A known origin's equality is validation, never a search for its target.
      final normalized = NovelReaderTextNormalization.project(
        origin.sourceText,
        trim:
            origin.policy == NovelReaderSourceTextPolicy.trimmedTextNode ||
            origin.policy == NovelReaderSourceTextPolicy.trimmedElementText,
      );
      if (normalized.text != origin.text ||
          (origin.policy == NovelReaderSourceTextPolicy.hardBreak &&
              origin.sourceText != '\n')) {
        _fail(NovelReaderNativeAnchorBindingFailure.origin);
      }
      final sourceLength = node.source.runeLength;
      budget.admitBoundaries(sourceLength + 1);
      final rawOffsets = _sourceOffsets(node, origin);
      if (rawOffsets == null) {
        unmapped.add(origin.path);
        continue;
      }
      segments.add(
        NovelReaderNativeAnchorSegment(
          sourceStart: node.source.runeStart,
          projection: NovelReaderSourceAnchorProjection(
            baseAnchor: NovelReaderTextAnchor(
              episodeId: episodeId,
              nodeId: origin.nodeId,
              formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
              textIdentity: target!.identity,
              isProgressPercentValid: false,
            ),
            semanticOffsetsBySourceRuneBoundary: [
              for (final raw in rawOffsets)
                origin.semanticCodePointStart + normalized.offsets[raw],
            ],
          ),
        ),
      );
    }
    if (target != null && semanticStart != target.runes.length) {
      _fail(NovelReaderNativeAnchorBindingFailure.origin);
    }
    return NovelReaderNativeAnchorMap(
      identity: bodyDocument.identity,
      episodeId: episodeId,
      sourceRuneLength: bodyDocument.sourceMap.runeLength,
      segments: segments,
      unmappedPaths: unmapped,
    );
  }
}

/// The semantic parser's element.text omits BR. Walk the same known IR subtree
/// to account for it explicitly. Removed/zero-source fallback content that
/// cannot be reconciled with the recorded raw text remains unmapped.
List<int>? _sourceOffsets(
  ForumBodyNode node,
  NovelReaderTextSourceOrigin origin,
) {
  switch (origin.policy) {
    case NovelReaderSourceTextPolicy.trimmedTextNode:
    case NovelReaderSourceTextPolicy.inlineTextNode:
      if (node is! ForumBodyText || node.text != origin.sourceText) {
        _fail(NovelReaderNativeAnchorBindingFailure.origin);
      }
      if (node.source.runeLength != origin.sourceText.runes.length) return null;
      return List.generate(node.source.runeLength + 1, (i) => i);
    case NovelReaderSourceTextPolicy.hardBreak:
      if (node is! ForumBodyElement ||
          node.kind != ForumBodyElementKind.hardBreak) {
        _fail(NovelReaderNativeAnchorBindingFailure.origin);
      }
      return node.source.runeLength == 1 ? const [0, 1] : null;
    case NovelReaderSourceTextPolicy.trimmedElementText:
      if (node is! ForumBodyElement || node.tag != 'a') {
        _fail(NovelReaderNativeAnchorBindingFailure.origin);
      }
      final text = StringBuffer();
      final offsets = <int>[0];
      var raw = 0;
      var source = node.source.runeStart;
      final pending = [node.children.iterator];
      while (pending.isNotEmpty) {
        if (!pending.last.moveNext()) {
          pending.removeLast();
          continue;
        }
        final child = pending.last.current;
        if (child.source.runeLength == 0) continue;
        if (child.source.runeStart != source) return null;
        if (child is ForumBodyText) {
          if (child.source.runeLength != child.text.runes.length) return null;
          text.write(child.text);
          for (var i = 0; i < child.source.runeLength; i++) {
            offsets.add(++raw);
            source++;
          }
        } else if (child is ForumBodyElement &&
            child.kind == ForumBodyElementKind.hardBreak) {
          if (child.source.runeLength != 1) return null;
          offsets.add(raw);
          source++;
        } else if (child is ForumBodyElement) {
          pending.add(child.children.iterator);
        }
      }
      if (text.toString() != origin.sourceText ||
          source != node.source.runeEnd) {
        return null;
      }
      return offsets;
  }
}

final class _SemanticTarget {
  _SemanticTarget(this.nodeId, this.index, this.runes, this.identity);
  final String nodeId;
  final int index;
  final List<int> runes;
  final String identity;

  static _SemanticTarget read(
    NovelReaderDocument document,
    String nodeId,
    _BindingBudget budget,
  ) {
    // Revision1 records historical root-block ordinals. Verify both the ID
    // spelling and actual block before using it; do not scan for equal text.
    final index = nodeId.startsWith('node-')
        ? int.tryParse(nodeId.substring(5))
        : null;
    if (index == null ||
        index < 0 ||
        nodeId != 'node-$index' ||
        index >= document.blocks.length ||
        document.blocks[index].anchorId != nodeId) {
      _fail(NovelReaderNativeAnchorBindingFailure.origin);
    }
    final text = document.blocks[index].novelPlainText;
    budget.admitSemantic(text.length);
    return _SemanticTarget(
      nodeId,
      index,
      text.runes.toList(growable: false),
      NovelReaderAnchorFormat.textIdentity(text),
    );
  }
}

final class _BindingBudget {
  _BindingBudget(this.limits) {
    if (limits.origins.maxEntries < 0 ||
        limits.origins.maxSourceCodeUnits < 0 ||
        limits.origins.maxPathCodeUnits < 0 ||
        limits.maxSourceBoundaries < 0 ||
        limits.maxSemanticCodeUnits < 0) {
      throw ArgumentError('Invalid native anchor binding limits');
    }
  }
  final NovelReaderNativeAnchorBindingLimits limits;
  var _boundaries = 0;
  var _semantic = 0;

  void admitOrigins(List<NovelReaderTextSourceOrigin> origins) {
    if (origins.length > limits.origins.maxEntries) {
      _fail(NovelReaderNativeAnchorBindingFailure.budget);
    }
    var source = 0;
    var paths = 0;
    for (final origin in origins) {
      source += origin.sourceText.length;
      paths += origin.path.length;
      if (source > limits.origins.maxSourceCodeUnits ||
          paths > limits.origins.maxPathCodeUnits) {
        _fail(NovelReaderNativeAnchorBindingFailure.budget);
      }
    }
  }

  void admitBoundaries(int count) {
    if (count > limits.maxSourceBoundaries - _boundaries) {
      _fail(NovelReaderNativeAnchorBindingFailure.budget);
    }
    _boundaries += count;
  }

  void admitSemantic(int count) {
    if (count > limits.maxSemanticCodeUnits - _semantic) {
      _fail(NovelReaderNativeAnchorBindingFailure.budget);
    }
    _semantic += count;
  }
}

Never _fail(NovelReaderNativeAnchorBindingFailure failure) =>
    throw NovelReaderNativeAnchorBindingException(failure);
