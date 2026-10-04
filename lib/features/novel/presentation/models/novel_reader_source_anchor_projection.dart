import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';

/// DOM source boundaries and persisted semantic offsets are different axes.
/// Values are absolute offsets in the semantic node, including substring bases.
final class NovelReaderSourceAnchorProjection {
  NovelReaderSourceAnchorProjection({
    required this.baseAnchor,
    required List<int> semanticOffsetsBySourceRuneBoundary,
  }) : semanticOffsetsBySourceRuneBoundary = List<int>.unmodifiable(
         semanticOffsetsBySourceRuneBoundary,
       ) {
    if (this.semanticOffsetsBySourceRuneBoundary.isEmpty) {
      throw ArgumentError('A projection needs at least the initial boundary.');
    }
    var previous = -1;
    for (final offset in this.semanticOffsetsBySourceRuneBoundary) {
      if (offset < previous || offset < 0) {
        throw ArgumentError(
          'Semantic offsets must be nonnegative and ordered.',
        );
      }
      previous = offset;
    }
  }

  final NovelReaderTextAnchor baseAnchor;
  final List<int> semanticOffsetsBySourceRuneBoundary;
  int get sourceRuneLength => semanticOffsetsBySourceRuneBoundary.length - 1;

  NovelReaderTextAnchor anchorAtSourceRune(int offset) => baseAnchor.copyWith(
    textOffset:
        semanticOffsetsBySourceRuneBoundary[offset.clamp(0, sourceRuneLength)],
  );

  NovelReaderSourceAnchorProjection subrange(int start, int end) {
    RangeError.checkValidRange(start, end, sourceRuneLength);
    return NovelReaderSourceAnchorProjection(
      baseAnchor: anchorAtSourceRune(start),
      semanticOffsetsBySourceRuneBoundary: semanticOffsetsBySourceRuneBoundary
          .sublist(start, end + 1),
    );
  }

  late final String cacheIdentity =
      '${baseAnchor.formatVersion}|${baseAnchor.textIdentity}|'
      '${baseAnchor.nodeId}|${NovelReaderAnchorFormat.textIdentity(semanticOffsetsBySourceRuneBoundary.join(','))}';
}
