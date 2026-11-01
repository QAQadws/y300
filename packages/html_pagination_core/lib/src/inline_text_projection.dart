import 'display_text_projection.dart';

/// A parent engine atom. Its display range still contains the actual child
/// text; an opaque/soft-space marker never acquires a new source coordinate.
final class HtmlInlineTextAtom {
  const HtmlInlineTextAtom._(
    this.index,
    this.displayStartUtf16,
    this.displayEndUtf16,
    this.engineUtf16,
    this.isSoftSpace,
  );
  final int index;
  final int displayStartUtf16;
  final int displayEndUtf16;
  final int engineUtf16;

  /// Engine-only collapsible glue between two actual opaque atoms. The caller
  /// still proves native width, trimmed visibility and original child glyphs.
  final bool isSoftSpace;
  int get engineEndUtf16 => engineUtf16 + 1;
}

/// A caret projected between display and parent engine coordinates.
final class HtmlInlineTextPosition {
  const HtmlInlineTextPosition._({
    required this.engineUtf16,
    required this.displayUtf16,
    required this.isExact,
  });
  final int engineUtf16;
  final int displayUtf16;

  /// False when rounded to a grapheme or atomic boundary. Source gaps require
  /// a separate source projection and can still make that result approximate.
  final bool isExact;
}

final class HtmlInlineTextLimitException implements Exception {
  const HtmlInlineTextLimitException();
}

/// Pure parent-engine/display/source coordinates for opaque inline children.
/// Each atom occupies one U+FFFC (or explicit soft SPACE) in the engine only.
/// Hit testing inside a child
/// must use that child's layout, rather than interpolate through this atom.
/// This map neither measures glyphs nor proves that a child has been painted.
final class HtmlInlineTextProjection {
  HtmlInlineTextProjection._(
    this.display,
    this.engineText,
    this.atoms,
    this.hasSoftSpaces,
  );
  static const revision = 2;

  factory HtmlInlineTextProjection.build({
    required HtmlDisplayTextProjection display,
    required List<({int startUtf16, int endUtf16})> atomicRanges,
    Set<int> softSpaceAtoms = const {},
    int maxAtoms = 512,
    int maxDisplayCodeUnits = 16384,
    int maxEngineCodeUnits = 16384,
  }) {
    if (maxAtoms < 0 || maxDisplayCodeUnits < 0 || maxEngineCodeUnits < 0) {
      throw ArgumentError('Invalid inline projection budget');
    }
    if (atomicRanges.length > maxAtoms ||
        display.text.length > maxDisplayCodeUnits) {
      throw const HtmlInlineTextLimitException();
    }
    final atoms = <HtmlInlineTextAtom>[];
    for (final index in softSpaceAtoms) {
      RangeError.checkValidIndex(index, atomicRanges, 'softSpaceAtoms');
      if (index == 0 ||
          index + 1 == atomicRanges.length ||
          softSpaceAtoms.contains(index - 1) ||
          softSpaceAtoms.contains(index + 1) ||
          atomicRanges[index - 1].endUtf16 != atomicRanges[index].startUtf16 ||
          atomicRanges[index].endUtf16 != atomicRanges[index + 1].startUtf16) {
        throw ArgumentError('Soft spaces require two adjacent opaque atoms');
      }
    }
    var previousEnd = 0;
    var removed = 0;
    for (final range in atomicRanges) {
      RangeError.checkValidRange(
        range.startUtf16,
        range.endUtf16,
        display.text.length,
      );
      if (range.startUtf16 < previousEnd ||
          range.startUtf16 == range.endUtf16 ||
          display.sourceAtUtf16(range.startUtf16).displayUtf16 !=
              range.startUtf16 ||
          display.sourceAtUtf16(range.endUtf16).displayUtf16 !=
              range.endUtf16) {
        throw ArgumentError(
          'Atoms require ordered, complete display graphemes',
        );
      }
      final soft = softSpaceAtoms.contains(atoms.length);
      if (soft &&
          !display.text
              .substring(range.startUtf16, range.endUtf16)
              .runes
              .every((r) => r == 32 || r == 9)) {
        throw ArgumentError(
          'Soft-space atoms require actual collapsible whitespace',
        );
      }
      atoms.add(
        HtmlInlineTextAtom._(
          atoms.length,
          range.startUtf16,
          range.endUtf16,
          range.startUtf16 - removed,
          soft,
        ),
      );
      removed += range.endUtf16 - range.startUtf16 - 1;
      previousEnd = range.endUtf16;
    }
    if (display.text.length - removed > maxEngineCodeUnits) {
      throw const HtmlInlineTextLimitException();
    }
    final engine = StringBuffer();
    previousEnd = 0;
    for (final atom in atoms) {
      engine.write(display.text.substring(previousEnd, atom.displayStartUtf16));
      engine.writeCharCode(atom.isSoftSpace ? 32 : 0xfffc);
      previousEnd = atom.displayEndUtf16;
    }
    engine.write(display.text.substring(previousEnd));
    return HtmlInlineTextProjection._(
      display,
      engine.toString(),
      List.unmodifiable(atoms),
      softSpaceAtoms.isNotEmpty,
    );
  }

  final HtmlDisplayTextProjection display;
  final String engineText;
  final List<HtmlInlineTextAtom> atoms;
  final bool hasSoftSpaces;

  HtmlInlineTextPosition engineAtDisplayUtf16(
    int offset, {
    HtmlProjectionAffinity affinity = HtmlProjectionAffinity.downstream,
  }) {
    final projected = display.sourceAtUtf16(offset, affinity: affinity);
    final value = projected.displayUtf16;
    final index = _lastAtomAtOrBefore(value, engine: false);
    if (index < 0) {
      return HtmlInlineTextPosition._(
        engineUtf16: value,
        displayUtf16: value,
        isExact: value == offset,
      );
    }
    final atom = atoms[index];
    if (value < atom.displayEndUtf16) {
      final start =
          value == atom.displayStartUtf16 ||
          affinity == HtmlProjectionAffinity.upstream;
      return HtmlInlineTextPosition._(
        engineUtf16: start ? atom.engineUtf16 : atom.engineEndUtf16,
        displayUtf16: start ? atom.displayStartUtf16 : atom.displayEndUtf16,
        isExact: value == offset && value == atom.displayStartUtf16,
      );
    }
    return HtmlInlineTextPosition._(
      engineUtf16: value - atom.displayEndUtf16 + atom.engineEndUtf16,
      displayUtf16: value,
      isExact: value == offset,
    );
  }

  HtmlInlineTextPosition displayAtEngineUtf16(
    int offset, {
    HtmlProjectionAffinity affinity = HtmlProjectionAffinity.downstream,
  }) {
    final rawDisplay = displayOffsetAtEngineUtf16(offset);
    final position = engineAtDisplayUtf16(rawDisplay, affinity: affinity);
    return HtmlInlineTextPosition._(
      engineUtf16: position.engineUtf16,
      displayUtf16: position.displayUtf16,
      isExact: position.isExact && position.engineUtf16 == offset,
    );
  }

  /// Raw UTF-16 transform for engine line geometry. A physical fallback row can
  /// end inside an ordinary grapheme: keep that offset while marking its break
  /// illegal via [displayAtEngineUtf16]. Never use this raw value as a caret,
  /// semantic anchor or legal display/HTML slice boundary.
  int displayOffsetAtEngineUtf16(int offset) {
    RangeError.checkValueInInterval(offset, 0, engineText.length, 'offset');
    final index = _lastAtomAtOrBefore(offset, engine: true);
    if (index < 0) return offset;
    final atom = atoms[index];
    return offset == atom.engineUtf16
        ? atom.displayStartUtf16
        : offset - atom.engineEndUtf16 + atom.displayEndUtf16;
  }

  HtmlProjectedSourcePosition sourceAtEngineUtf16(
    int offset, {
    HtmlProjectionAffinity affinity = HtmlProjectionAffinity.downstream,
  }) {
    final position = displayAtEngineUtf16(offset, affinity: affinity);
    final source = display.sourceAtUtf16(
      position.displayUtf16,
      affinity: affinity,
    );
    return HtmlProjectedSourcePosition(
      sourceRune: source.sourceRune,
      displayUtf16: position.displayUtf16,
      isExact: position.isExact && source.isExact,
    );
  }

  /// Converts a verified engine line/window without cutting a grapheme/atom.
  /// The returned display interval is not proof of visible source coverage.
  ({int startUtf16, int endUtf16}) displayRangeForEngineRange({
    required int startUtf16,
    required int endUtf16,
  }) {
    RangeError.checkValidRange(startUtf16, endUtf16, engineText.length);
    final start = displayAtEngineUtf16(startUtf16);
    final end = displayAtEngineUtf16(endUtf16);
    if (!start.isExact || !end.isExact) {
      throw ArgumentError('Engine range must contain complete inline units');
    }
    return (startUtf16: start.displayUtf16, endUtf16: end.displayUtf16);
  }

  /// Process-local map identity only. Geometry/style/owner inputs remain the
  /// renderer's responsibility, and hash collisions require deep equality.
  late final int mappingHash = Object.hash(
    display.sourceMappingHash,
    Object.hashAll(
      atoms.map(
        (atom) => Object.hash(
          atom.displayStartUtf16,
          atom.displayEndUtf16,
          atom.isSoftSpace,
        ),
      ),
    ),
  );

  bool hasSameMapping(HtmlInlineTextProjection other) {
    if (identical(this, other)) return true;
    if (mappingHash != other.mappingHash ||
        !display.hasSameSourceMapping(other.display) ||
        atoms.length != other.atoms.length) {
      return false;
    }
    for (var index = 0; index < atoms.length; index++) {
      if (atoms[index].displayStartUtf16 !=
              other.atoms[index].displayStartUtf16 ||
          atoms[index].displayEndUtf16 != other.atoms[index].displayEndUtf16 ||
          atoms[index].isSoftSpace != other.atoms[index].isSoftSpace) {
        return false;
      }
    }
    return true;
  }

  int _lastAtomAtOrBefore(int offset, {required bool engine}) {
    var low = 0;
    var high = atoms.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final value = engine
          ? atoms[middle].engineUtf16
          : atoms[middle].displayStartUtf16;
      if (value <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }
}
