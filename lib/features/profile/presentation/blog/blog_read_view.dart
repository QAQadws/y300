import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Starts reads only for a mounted active view and cancels on route teardown.
class BlogReadView<T> extends StatefulWidget {
  const BlogReadView({
    super.key,
    required this.listenable,
    required this.setActive,
    required this.builder,
    this.isActive = true,
  });

  final ValueListenable<T> listenable;
  final Future<void> Function(bool active) setActive;
  final ValueWidgetBuilder<T> builder;
  final bool isActive;

  @override
  State<BlogReadView<T>> createState() => _BlogReadViewState<T>();
}

class _BlogReadViewState<T> extends State<BlogReadView<T>> {
  bool _routeIsCurrent = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    unawaited(widget.setActive(widget.isActive && _routeIsCurrent));
  }

  @override
  void didUpdateWidget(covariant BlogReadView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      unawaited(widget.setActive(widget.isActive && _routeIsCurrent));
    }
  }

  @override
  void dispose() {
    unawaited(widget.setActive(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<T>(
    valueListenable: widget.listenable,
    builder: widget.builder,
  );
}
