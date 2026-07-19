enum ReaderSequencePositionKind { image, tail, advance }

/// Logical position in a reader sequence.
///
/// Image indexes remain the only positions that affect image progress or
/// slider seeking. Tail and advance positions are neutral content surfaces.
class ReaderSequencePosition {
  const ReaderSequencePosition.image(this.index)
    : kind = ReaderSequencePositionKind.image,
      tailId = null,
      advanceId = null;

  const ReaderSequencePosition.tail(this.tailId)
    : kind = ReaderSequencePositionKind.tail,
      index = null,
      advanceId = null;

  const ReaderSequencePosition.advance(this.advanceId)
    : kind = ReaderSequencePositionKind.advance,
      index = null,
      tailId = null;

  final ReaderSequencePositionKind kind;
  final int? index;
  final String? tailId;
  final String? advanceId;

  bool get isImage => kind == ReaderSequencePositionKind.image;
  bool get isTail => kind == ReaderSequencePositionKind.tail;
  bool get isAdvance => kind == ReaderSequencePositionKind.advance;
}
