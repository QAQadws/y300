part of 'forum_body_ruby_group_metrics.dart';

/// Numeric counterpart of one logical parent atom. It carries no
/// source association, native lease or owner; those remain in the atom plan.
sealed class ForumBodyRubyAtomMetrics {
  const ForumBodyRubyAtomMetrics();
  const factory ForumBodyRubyAtomMetrics.column(
    ForumBodyRubyGroupMetrics value,
  ) = ForumBodyRubyColumnMetrics;
  const factory ForumBodyRubyAtomMetrics.segment(
    ForumBodyRubySegmentMetrics value,
  ) = ForumBodyRubyComponentMetrics;
  const factory ForumBodyRubyAtomMetrics.softSpace(
    ForumBodyRubySoftSpaceMetrics value,
  ) = ForumBodyRubySpaceMetrics;
  Size get size;
  double get baseline;
  String get alignmentSignature;
  PlaceholderDimensions get placeholderDimensions;
}

/// Baseline boxes keep their own geometry; they never join an annotation level.
final class ForumBodyTextBaselineAtomMetrics extends ForumBodyRubyAtomMetrics {
  const ForumBodyTextBaselineAtomMetrics(this.value);
  final ForumBodyTextBaselineMetrics value;
  @override
  Size get size => value.size;
  @override
  double get baseline => value.baseline;
  @override
  String get alignmentSignature => 'text-baseline';
  @override
  PlaceholderDimensions get placeholderDimensions =>
      value.placeholderDimensions;
}

final class ForumBodyRubySpaceMetrics extends ForumBodyRubyAtomMetrics {
  const ForumBodyRubySpaceMetrics(this.value);
  final ForumBodyRubySoftSpaceMetrics value;
  @override
  Size get size => value.size;
  @override
  double get baseline => value.baseline;
  @override
  String get alignmentSignature => value.alignmentSignature;
  @override
  PlaceholderDimensions get placeholderDimensions =>
      value.placeholderDimensions;
}

final class ForumBodyRubyColumnMetrics extends ForumBodyRubyAtomMetrics {
  const ForumBodyRubyColumnMetrics(this.value);
  final ForumBodyRubyGroupMetrics value;
  @override
  Size get size => value.size;
  @override
  double get baseline => value.baseline;
  @override
  String get alignmentSignature => value.alignmentSignature;
  @override
  PlaceholderDimensions get placeholderDimensions =>
      value.placeholderDimensions;
}

final class ForumBodyRubyComponentMetrics extends ForumBodyRubyAtomMetrics {
  const ForumBodyRubyComponentMetrics(this.value);
  final ForumBodyRubySegmentMetrics value;
  @override
  Size get size => value.size;
  @override
  double get baseline => value.baseline;
  @override
  String get alignmentSignature => value.alignmentSignature;
  @override
  PlaceholderDimensions get placeholderDimensions =>
      value.placeholderDimensions;
}

/// Internal dispatch only; each variant uses its existing bounded worker.
final class ForumBodyRubyAtomAlignment {
  ForumBodyRubyAtomAlignment({
    required ForumBodyRubyAtomMetrics atom,
    required ForumBodyRubyLevelMetrics level,
    bool prepareResult = false,
  }) : _column = switch (atom) {
         ForumBodyRubyColumnMetrics(:final value) =>
           ForumBodyRubyColumnAlignment(
             column: value,
             level: level,
             prepareResult: prepareResult,
           ),
         _ => null,
       },
       _segment = switch (atom) {
         ForumBodyRubyComponentMetrics(:final value) =>
           ForumBodyRubySegmentAlignment(
             segment: value,
             level: level,
             prepareResult: prepareResult,
           ),
         _ => null,
       },
       _space = switch (atom) {
         ForumBodyRubySpaceMetrics(:final value) =>
           ForumBodyRubySoftSpaceAlignment(
             softSpace: value,
             level: level,
             prepareResult: prepareResult,
           ),
         _ => null,
       } {
    if (atom is ForumBodyTextBaselineAtomMetrics) {
      throw ArgumentError('Baseline text does not join ruby levels');
    }
  }
  final ForumBodyRubyColumnAlignment? _column;
  final ForumBodyRubySegmentAlignment? _segment;
  final ForumBodyRubySoftSpaceAlignment? _space;
  bool get isComplete =>
      _column?.isComplete ?? _segment?.isComplete ?? _space!.isComplete;
  bool get hasChanges =>
      _column?.hasChanges ?? _segment?.hasChanges ?? _space!.hasChanges;
  ForumBodyRubyAtomMetrics get result => _column != null
      ? ForumBodyRubyColumnMetrics(_column!.result)
      : _segment != null
      ? ForumBodyRubyComponentMetrics(_segment.result)
      : ForumBodyRubySpaceMetrics(_space!.result);
  int advance({required int maxParts}) => _column != null
      ? _column!.advance(maxParts: maxParts)
      : _segment != null
      ? _segment.advance(maxParts: maxParts)
      : _space!.advance(maxParts: maxParts);
}
