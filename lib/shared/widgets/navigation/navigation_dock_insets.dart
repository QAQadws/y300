import 'package:flutter/widgets.dart';

/// The dock overlaps the viewport. Consume its height at the trailing edge of
/// a scrollable so its last item can come to rest above the dock.
class NavigationDockInsets extends InheritedWidget {
  const NavigationDockInsets({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static double bottomOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NavigationDockInsets>()
          ?.bottom ??
      0;

  static EdgeInsets scrollPaddingOf(BuildContext context, EdgeInsets base) =>
      base.copyWith(bottom: base.bottom + bottomOf(context));

  @override
  bool updateShouldNotify(NavigationDockInsets oldWidget) =>
      bottom != oldWidget.bottom;
}
