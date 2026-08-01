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
  }) : panelBuilder = null;

  /// Creates an action whose content is hosted by the active editor surface.
  ///
  /// Quill embeds the content in its keyboard-replacement tool panel. Source
  /// mode presents it with the same bottom-panel convention as its other
  /// feature pickers.
  const ComposerToolbarAction.panel({
    required this.key,
    required this.icon,
    required this.tooltip,
    required this.panelBuilder,
  }) : onPressed = null;

  final Key key;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final WidgetBuilder? panelBuilder;

  bool get isAvailable => onPressed != null || panelBuilder != null;
}
