import 'package:flutter/material.dart';

/// Presentation-only extension point for feature-specific composer actions.
///
/// The shared toolbars render the action but never interpret its business
/// meaning. This keeps post-edit actions out of reply/posting toolbar code.
final class ComposerToolbarAction {
  const ComposerToolbarAction({
    required this.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Key key;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
}
