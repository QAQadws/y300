import 'package:flutter/material.dart';

/// Keeps composer AppBar actions from inheriting the global IconButtonTheme,
/// which is tuned for surface buttons and can look muted on colored AppBars.
ButtonStyle composerAppBarActionStyle(BuildContext context) {
  final theme = Theme.of(context);
  final appBarTheme = theme.appBarTheme;
  final foreground =
      appBarTheme.actionsIconTheme?.color ??
      appBarTheme.iconTheme?.color ??
      appBarTheme.foregroundColor ??
      theme.colorScheme.onSurface;
  return IconButton.styleFrom(
    foregroundColor: foreground,
    disabledForegroundColor: foreground.withValues(alpha: 0.38),
  );
}
