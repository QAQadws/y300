import 'dart:async';

import 'package:flutter/material.dart';

/// Suppresses feedback for quick reads and keeps longer waits static.
class DelayedLoadingStatus extends StatefulWidget {
  const DelayedLoadingStatus({
    super.key,
    required this.label,
    this.beforeDelay,
  });

  final String label;
  final Widget? beforeDelay;

  @override
  State<DelayedLoadingStatus> createState() => _DelayedLoadingStatusState();
}

class _DelayedLoadingStatusState extends State<DelayedLoadingStatus> {
  late final Timer _delay;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _delay = Timer(const Duration(milliseconds: 180), () {
      setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _delay.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.beforeDelay ?? const SizedBox.shrink();
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        widget.label,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
