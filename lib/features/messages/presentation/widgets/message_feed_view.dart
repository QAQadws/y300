import 'package:flutter/material.dart';
import 'package:y300/features/messages/presentation/message_feed_controller.dart';

/// Each mounted view owns its activity independently of other feed consumers.
class MessageFeedView<P> extends StatefulWidget {
  const MessageFeedView({
    super.key,
    required this.controller,
    required this.builder,
    this.isActive = true,
  });

  final MessageFeedController<P> controller;
  final Widget Function(BuildContext, MessageFeedState<P>) builder;
  final bool isActive;

  @override
  State<MessageFeedView<P>> createState() => _MessageFeedViewState<P>();
}

class _MessageFeedViewState<P> extends State<MessageFeedView<P>>
    with WidgetsBindingObserver {
  final _owner = Object();
  AppLifecycleState? _lifecycleState;

  @override
  void initState() {
    super.initState();
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  void _syncActivity() {
    // TabBarView can retain old child properties during a page animation. The
    // shell's effective ticker mode still changes when that animation is hidden.
    final tickersEnabled = TickerMode.valuesOf(context).enabled;
    widget.controller.setActive(
      widget.isActive &&
          (_lifecycleState == null ||
              _lifecycleState == AppLifecycleState.resumed) &&
          tickersEnabled &&
          (ModalRoute.isCurrentOf(context) ?? true),
      owner: _owner,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (mounted) _syncActivity();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncActivity();
  }

  @override
  void didUpdateWidget(covariant MessageFeedView<P> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.setActive(false, owner: _owner);
    }
    _syncActivity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.setActive(false, owner: _owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.controller,
    builder: (context, state, _) => widget.builder(context, state),
  );
}
