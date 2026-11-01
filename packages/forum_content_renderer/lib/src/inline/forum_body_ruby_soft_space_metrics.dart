part of 'forum_body_ruby_group_metrics.dart';

/// An actual whitespace member's numeric font box. Null rank is base whitespace;
/// using the shared font-box value does not turn that member into an RT.
final class ForumBodyRubySoftSpaceMeasuredMember {
  const ForumBodyRubySoftSpaceMeasuredMember({
    required this.annotationIndex,
    required this.font,
  });
  final int? annotationIndex;
  final ForumBodyRubyAnnotationMetrics font;
}

final class ForumBodyRubySoftSpacePlacedMember {
  const ForumBodyRubySoftSpacePlacedMember._({
    required this.input,
    required this.offset,
    required this.bandTop,
    required this.bandBottom,
  });
  final ForumBodyRubySoftSpaceMeasuredMember input;
  final Offset offset;
  final double bandTop;
  final double bandBottom;
}

/// Pure geometry of a breakable gap between real columns. A missing base has
/// zero base extents; missing ranks remain numbers and never borrow a font.
/// This value owns no source, native lease, coverage proof or reading position.
final class ForumBodyRubySoftSpaceMetrics {
  factory ForumBodyRubySoftSpaceMetrics.compose({
    required List<ForumBodyRubySoftSpaceMeasuredMember> members,
    required List<ForumBodyRubySide> sides,
    TextDirection direction = TextDirection.ltr,
    double maxWidth = 16384,
    ForumBodyRubyLevelMetrics? level,
  }) {
    final work = ForumBodyRubySoftSpaceComposition(
      members: members,
      sides: sides,
      direction: direction,
      maxWidth: maxWidth,
      level: level,
    );
    while (!work.isComplete) {
      work.advance(maxParts: 32);
    }
    return work.result;
  }
  ForumBodyRubySoftSpaceMetrics._({
    required this.size,
    required this.baseline,
    required this.level,
    required this.direction,
    required this.alignmentSignature,
    required List<ForumBodyRubySoftSpacePlacedMember> members,
    required List<ForumBodyRubySoftSpaceMeasuredMember> inputs,
    required List<ForumBodyRubySide> sides,
  }) : members = UnmodifiableListView(members),
       _inputs = UnmodifiableListView(inputs),
       _sides = UnmodifiableListView(sides);
  static const revision = 1;
  final Size size;
  final double baseline;
  final ForumBodyRubyLevelMetrics level;
  final TextDirection direction;
  final String alignmentSignature;
  final List<ForumBodyRubySoftSpacePlacedMember> members;
  final List<ForumBodyRubySoftSpaceMeasuredMember> _inputs;
  final List<ForumBodyRubySide> _sides;
  PlaceholderDimensions get placeholderDimensions => PlaceholderDimensions(
    size: size,
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: baseline,
  );
}

enum _SoftSpacePhase {
  ranks,
  members,
  levels,
  positions,
  publish,
  ready,
  failed,
}

/// One rank, member or publication per work unit. Uses the same font boxes and
/// vertical stack as columns/segments; it never shapes text or records pictures.
/// Optional row targets only change vertical coordinates, not widths or order.
final class ForumBodyRubySoftSpaceComposition {
  // Existing immutable numeric inputs are borrowed, not rescanned/copied at
  // the start of a bounded alignment unit. No source or native lease is held.
  ForumBodyRubySoftSpaceComposition._aligned(
    ForumBodyRubySoftSpaceMetrics source,
    ForumBodyRubyLevelMetrics target,
  ) : _members = source._inputs,
      _sides = source._sides,
      direction = source.direction,
      maxWidth = 16384,
      level = target;

  ForumBodyRubySoftSpaceComposition({
    required List<ForumBodyRubySoftSpaceMeasuredMember> members,
    required List<ForumBodyRubySide> sides,
    this.direction = TextDirection.ltr,
    this.maxWidth = 16384,
    this.level,
  }) : _members = List.of(members),
       _sides = List.of(sides) {
    if (members.isEmpty ||
        sides.isEmpty ||
        !maxWidth.isFinite ||
        maxWidth <= 0 ||
        maxWidth > 16384 ||
        (level != null && level!.annotations.length != sides.length)) {
      ForumBodyRubyGroupMetrics._invalid();
    }
  }
  final List<ForumBodyRubySoftSpaceMeasuredMember> _members;
  final List<ForumBodyRubySide> _sides;
  final TextDirection direction;
  final double maxWidth;
  final ForumBodyRubyLevelMetrics? level;
  final _ranks = <ForumBodyRubyAnnotationLevelMetrics>[];
  final _widths = <double>[0];
  final _within = <double>[];
  final _positions = <({double baseline, double top, double bottom})>[];
  final _placed = <ForumBodyRubySoftSpacePlacedMember>[];
  final _signature = StringBuffer();
  var _phase = _SoftSpacePhase.ranks;
  var _cursor = 0;
  var _previousRank = -1;
  var _baseAscent = 0.0;
  var _baseDescent = 0.0;
  var _width = 0.0;
  _RubyStack? _stack;
  ForumBodyRubyLevelMetrics? _effectiveLevel;
  ForumBodyRubySoftSpaceMetrics? _result;
  bool get isComplete => _phase == _SoftSpacePhase.ready;
  ForumBodyRubySoftSpaceMetrics get result {
    if (!isComplete) throw StateError('Ruby soft-space geometry is incomplete');
    return _result!;
  }

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (isComplete || _phase == _SoftSpacePhase.failed) {
      throw StateError('Ruby soft-space composition is not active');
    }
    try {
      return _advance(maxParts);
    } catch (_) {
      _phase = _SoftSpacePhase.failed;
      rethrow;
    }
  }

  int _advance(int maxParts) {
    var parts = 0;
    while (parts < maxParts && !isComplete) {
      switch (_phase) {
        case _SoftSpacePhase.ranks:
          _ranks.add(
            ForumBodyRubyAnnotationLevelMetrics._(
              side: _sides[_cursor],
              hasAnnotation: false,
              ascent: 0,
              descent: 0,
              gap: 0,
            ),
          );
          _widths.add(0);
          parts++;
          if (++_cursor == _sides.length) {
            _cursor = 0;
            _phase = _SoftSpacePhase.members;
          }
        case _SoftSpacePhase.members:
          final member = _members[_cursor];
          final rank = member.annotationIndex ?? -1;
          final font = member.font;
          if (rank < _previousRank ||
              (member.annotationIndex != null && rank < 0) ||
              rank >= _sides.length ||
              !font.hasAnnotation ||
              !font.bounds.width.isFinite ||
              font.bounds.width < 0 ||
              !font.ascent.isFinite ||
              font.ascent < 0 ||
              !font.descent.isFinite ||
              font.descent < 0 ||
              (rank == -1 && font.gap != 0)) {
            ForumBodyRubyGroupMetrics._invalid();
          }
          _previousRank = rank;
          _within.add(_widths[rank + 1]);
          _widths[rank + 1] += font.bounds.width;
          _width = math.max(_width, _widths[rank + 1]);
          if (_width > maxWidth) {
            throw const ForumBodyRubyGroupException(
              ForumBodyRubyGroupFailure.overflow,
            );
          }
          if (rank == -1) {
            _baseAscent = math.max(_baseAscent, font.ascent);
            _baseDescent = math.max(_baseDescent, font.descent);
          } else {
            if (_sides[rank] != font.side) ForumBodyRubyGroupMetrics._invalid();
            _ranks[rank] = _ranks[rank]._include(font);
          }
          parts++;
          if (++_cursor == _members.length) {
            _effectiveLevel =
                level ??
                ForumBodyRubyLevelMetrics._owned(
                  baseAscent: _baseAscent,
                  baseDescent: _baseDescent,
                  annotations: _ranks,
                );
            const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
            if (_baseAscent > _effectiveLevel!.baseAscent + tolerance ||
                _baseDescent > _effectiveLevel!.baseDescent + tolerance) {
              ForumBodyRubyGroupMetrics._invalid();
            }
            _stack = _RubyStack(
              _effectiveLevel!.baseAscent,
              _effectiveLevel!.baseDescent,
            );
            _cursor = 0;
            _phase = _SoftSpacePhase.levels;
          }
        case _SoftSpacePhase.levels:
          final target = _effectiveLevel!.annotations[_cursor];
          if (!target._containsLevel(_ranks[_cursor])) {
            ForumBodyRubyGroupMetrics._invalid();
          }
          _positions.add(_stack!.append(target));
          _signature.write(_sides[_cursor].index);
          parts++;
          if (++_cursor == _sides.length) {
            final height = _stack!.over + _stack!.under;
            if (!height.isFinite || height <= 0 || height > 16384) {
              ForumBodyRubyGroupMetrics._invalid();
            }
            _cursor = 0;
            _phase = _SoftSpacePhase.positions;
          }
        case _SoftSpacePhase.positions:
          final member = _members[_cursor];
          final rank = member.annotationIndex;
          final font = member.font;
          final group = rank == null ? 0 : rank + 1;
          final start = (_width - _widths[group]) / 2 + _within[_cursor];
          final left = direction == TextDirection.ltr
              ? start
              : _width - start - font.bounds.width;
          final position = rank == null
              ? (
                  baseline: 0.0,
                  top: -_effectiveLevel!.baseAscent,
                  bottom: _effectiveLevel!.baseDescent,
                )
              : _positions[rank];
          _placed.add(
            ForumBodyRubySoftSpacePlacedMember._(
              input: member,
              offset: Offset(
                left - font.bounds.left,
                _stack!.over + position.baseline - font.fontBaseline,
              ),
              bandTop: _stack!.over + position.top,
              bandBottom: _stack!.over + position.bottom,
            ),
          );
          parts++;
          if (++_cursor == _members.length) _phase = _SoftSpacePhase.publish;
        case _SoftSpacePhase.publish:
          _result = ForumBodyRubySoftSpaceMetrics._(
            size: Size(_width, _stack!.over + _stack!.under),
            baseline: _stack!.over,
            level: _effectiveLevel!,
            direction: direction,
            alignmentSignature: _signature.toString(),
            members: _placed,
            inputs: _members,
            sides: _sides,
          );
          parts++;
          _phase = _SoftSpacePhase.ready;
        case _SoftSpacePhase.ready:
        case _SoftSpacePhase.failed:
          throw StateError('Ruby soft-space composition has no work');
      }
    }
    return parts;
  }
}

/// The existing composer is the only positioning path. Check all original ranks
/// before preparing a result; a shifted early rank cannot hide a bad later one.
final class ForumBodyRubySoftSpaceAlignment {
  ForumBodyRubySoftSpaceAlignment({
    required this.softSpace,
    required this.level,
    this.prepareResult = false,
  }) : _source = _RubyStack(
         softSpace.level.baseAscent,
         softSpace.level.baseDescent,
       ),
       _target = _RubyStack(level.baseAscent, level.baseDescent) {
    const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
    if (softSpace.level.annotations.length != level.annotations.length ||
        softSpace.level.baseAscent > level.baseAscent + tolerance ||
        softSpace.level.baseDescent > level.baseDescent + tolerance) {
      ForumBodyRubyGroupMetrics._invalid();
    }
  }
  final ForumBodyRubySoftSpaceMetrics softSpace;
  final ForumBodyRubyLevelMetrics level;
  final bool prepareResult;
  final _RubyStack _source;
  final _RubyStack _target;
  var _rank = 0;
  var _changed = false;
  var _failed = false;
  ForumBodyRubySoftSpaceComposition? _positioning;
  bool get isComplete =>
      !_failed &&
      _rank == level.annotations.length &&
      (!prepareResult || (_positioning?.isComplete ?? false));
  bool get hasChanges {
    if (!isComplete) {
      throw StateError('Ruby soft-space alignment is incomplete');
    }
    return _changed;
  }

  ForumBodyRubySoftSpaceMetrics get result {
    if (!isComplete || !prepareResult) {
      throw StateError('Ruby soft-space alignment result is incomplete');
    }
    return _positioning!.result;
  }

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (isComplete || _failed) {
      throw StateError('Ruby soft-space alignment is not active');
    }
    try {
      var parts = 0;
      while (_rank < level.annotations.length && parts < maxParts) {
        final source = softSpace.level.annotations[_rank];
        final target = level.annotations[_rank];
        if (!target._containsLevel(source)) {
          ForumBodyRubyGroupMetrics._invalid();
        }
        final before = _source.append(source);
        final after = _target.append(target);
        const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
        if ((source.hasAnnotation &&
                (before.baseline - after.baseline).abs() > tolerance) ||
            (_source.over - _target.over).abs() > tolerance ||
            (_source.under - _target.under).abs() > tolerance) {
          _changed = true;
        }
        _rank++;
        parts++;
      }
      if (_rank == level.annotations.length &&
          prepareResult &&
          parts < maxParts) {
        final positioning = _positioning ??=
            ForumBodyRubySoftSpaceComposition._aligned(softSpace, level);
        parts += positioning.advance(maxParts: maxParts - parts);
      }
      return parts;
    } catch (_) {
      _failed = true;
      rethrow;
    }
  }
}
