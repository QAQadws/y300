import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../document/forum_body_document.dart';

/// A half-open DOM source code-point interval in one verified document.
/// It is independent of layout, display UTF-16 and application anchors.
@immutable
final class ForumBodySourceRange {
  const ForumBodySourceRange(this.identity, this.startRune, this.endRune)
    : assert(startRune >= 0),
      assert(endRune > startRune);

  final ForumBodyIdentity identity;
  final int startRune, endRune;

  @override
  bool operator ==(Object other) =>
      other is ForumBodySourceRange &&
      other.identity == identity &&
      other.startRune == startRune &&
      other.endRune == endRune;

  @override
  int get hashCode => Object.hash(identity, startRune, endRune);
}

/// Paints current source ranges on descendant native pages and table slices.
/// The host chooses the ranges and color and keeps the list immutable.
final class ForumBodyTextHighlight extends InheritedWidget {
  const ForumBodyTextHighlight({
    required this.ranges,
    required this.color,
    required super.child,
    super.key,
  });

  final List<ForumBodySourceRange> ranges;
  final Color color;

  static ForumBodyTextHighlight? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ForumBodyTextHighlight>();

  @override
  bool updateShouldNotify(ForumBodyTextHighlight oldWidget) =>
      oldWidget.color != color || !listEquals(oldWidget.ranges, ranges);
}
