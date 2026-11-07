import 'display_text_projection.dart';

final class HtmlTextBandChild {
  const HtmlTextBandChild._(this.index, this.engineStartUtf16, this.display);
  final int index;
  final int engineStartUtf16;
  final HtmlDisplayTextProjection display;
  int get engineEndUtf16 => engineStartUtf16 + display.text.length;
}

final class HtmlTextBandLimitException implements Exception {
  const HtmlTextBandLimitException();
}

/// Independent child text windows in one native engine band. Virtual newline /
/// spacer characters exist only in engineText, never in source/display text.
/// Children retain separate graphemes and real source affinity. This map does
/// not measure fonts, own glyph resources or prove visible semantic coverage.
final class HtmlTextBandProjection {
  HtmlTextBandProjection._(this.engineText, this.children);
  static const revision = 1;
  static const separator = '\n\u200b\n';

  factory HtmlTextBandProjection.build(
    List<HtmlDisplayTextProjection> children, {
    int maxChildren = 64,
    int maxDisplayCodeUnits = 16384,
    int maxEngineCodeUnits = 16573,
  }) {
    if (maxChildren < 0 || maxDisplayCodeUnits < 0 || maxEngineCodeUnits < 0) {
      throw ArgumentError('Invalid text band budget');
    }
    if (children.length > maxChildren) throw const HtmlTextBandLimitException();
    var displayLength = 0;
    var engineLength = 0;
    int? previousEnd;
    final windows = <HtmlTextBandChild>[];
    for (final child in children) {
      final start = child
          .sourceAtUtf16(
            0,
            affinity: child.text.isEmpty
                ? HtmlProjectionAffinity.upstream
                : HtmlProjectionAffinity.downstream,
          )
          .sourceRune;
      final end = child
          .sourceAtUtf16(
            child.text.length,
            affinity: child.text.isEmpty
                ? HtmlProjectionAffinity.downstream
                : HtmlProjectionAffinity.upstream,
          )
          .sourceRune;
      if (previousEnd != null && start < previousEnd) {
        throw ArgumentError(
          'Text band children overlap or reverse source order',
        );
      }
      previousEnd = end;
      displayLength += child.text.length;
      engineLength += windows.isEmpty ? 0 : separator.length;
      windows.add(HtmlTextBandChild._(windows.length, engineLength, child));
      engineLength += child.text.length;
      if (displayLength > maxDisplayCodeUnits ||
          engineLength > maxEngineCodeUnits) {
        throw const HtmlTextBandLimitException();
      }
    }
    return HtmlTextBandProjection._(
      children.map((child) => child.text).join(separator),
      List.unmodifiable(windows),
    );
  }

  final String engineText;
  final List<HtmlTextBandChild> children;

  /// A hit belonging to a known child. An engine hit on another row/spacer is
  /// clamped and marked approximate, never assigned a virtual source offset.
  HtmlProjectedSourcePosition sourceAtChildEngineUtf16(
    int childIndex,
    int engineOffset, {
    HtmlProjectionAffinity affinity = HtmlProjectionAffinity.downstream,
  }) {
    RangeError.checkValidIndex(childIndex, children, 'childIndex');
    RangeError.checkValueInInterval(
      engineOffset,
      0,
      engineText.length,
      'engineOffset',
    );
    final child = children[childIndex];
    final clamped = engineOffset.clamp(
      child.engineStartUtf16,
      child.engineEndUtf16,
    );
    final position = child.display.sourceAtUtf16(
      clamped - child.engineStartUtf16,
      affinity: affinity,
    );
    return HtmlProjectedSourcePosition(
      sourceRune: position.sourceRune,
      displayUtf16: position.displayUtf16,
      isExact: clamped == engineOffset && position.isExact,
    );
  }

  /// Child-local selection expands to complete child display graphemes; it can
  /// never include an engine-only separator or another child's text.
  ({int startUtf16, int endUtf16}) engineRangeForChildSelection(
    int childIndex, {
    required int startUtf16,
    required int endUtf16,
  }) {
    RangeError.checkValidIndex(childIndex, children, 'childIndex');
    final child = children[childIndex];
    RangeError.checkValidRange(startUtf16, endUtf16, child.display.text.length);
    if (startUtf16 == endUtf16) {
      final offset = child.display.sourceAtUtf16(startUtf16).displayUtf16;
      return (
        startUtf16: child.engineStartUtf16 + offset,
        endUtf16: child.engineStartUtf16 + offset,
      );
    }
    final start = child.display
        .sourceAtUtf16(startUtf16, affinity: HtmlProjectionAffinity.upstream)
        .displayUtf16;
    final end = child.display.sourceAtUtf16(endUtf16).displayUtf16;
    return (
      startUtf16: child.engineStartUtf16 + start,
      endUtf16: child.engineStartUtf16 + end,
    );
  }
}
