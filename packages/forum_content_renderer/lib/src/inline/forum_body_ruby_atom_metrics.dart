part of 'forum_body_ruby_group_metrics.dart';

/// Numeric counterpart of an indivisible parent placeholder. It carries no
/// source association, native lease or owner; those remain in the atom plan.
sealed class ForumBodyRubyAtomMetrics {
  const ForumBodyRubyAtomMetrics();
  const factory ForumBodyRubyAtomMetrics.column(
    ForumBodyRubyGroupMetrics value,
  ) = ForumBodyRubyColumnMetrics;
  const factory ForumBodyRubyAtomMetrics.segment(
    ForumBodyRubySegmentMetrics value,
  ) = ForumBodyRubyComponentMetrics;
  Size get size;
  double get baseline;
  String get alignmentSignature;
  PlaceholderDimensions get placeholderDimensions;
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

/// Internal dispatch only; both variants use their existing bounded workers.
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
       };
  final ForumBodyRubyColumnAlignment? _column;
  final ForumBodyRubySegmentAlignment? _segment;
  bool get isComplete => _column?.isComplete ?? _segment!.isComplete;
  bool get hasChanges => _column?.hasChanges ?? _segment!.hasChanges;
  ForumBodyRubyAtomMetrics get result => _column != null
      ? ForumBodyRubyColumnMetrics(_column!.result)
      : ForumBodyRubyComponentMetrics(_segment!.result);
  int advance({required int maxParts}) => _column != null
      ? _column!.advance(maxParts: maxParts)
      : _segment!.advance(maxParts: maxParts);
}
