import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Shared status colors for forum and user-topic cards.
@immutable
final class ForumThreadBadgeColors {
  const ForumThreadBadgeColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;

  factory ForumThreadBadgeColors.resolve(
    ThemeData theme,
    ForumThreadBadgeKind kind,
  ) {
    final colors =
        theme.extension<ForumThreadBadgeTheme>() ??
        ForumThreadBadgeTheme.fromColorScheme(
          theme.colorScheme,
          standardBackground: theme.appBarTheme.backgroundColor,
          standardForeground: theme.appBarTheme.foregroundColor,
        );
    return switch (kind) {
      ForumThreadBadgeKind.closed => colors.closed,
      ForumThreadBadgeKind.digest => colors.digest,
      ForumThreadBadgeKind.sticky => colors.sticky,
      _ => colors.standard,
    };
  }

  ForumThreadBadgeColors lerp(ForumThreadBadgeColors other, double t) {
    return ForumThreadBadgeColors(
      background: Color.lerp(background, other.background, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
    );
  }
}

/// Theme-owned marker roles, independent of the card rendering their labels.
@immutable
final class ForumThreadBadgeTheme
    extends ThemeExtension<ForumThreadBadgeTheme> {
  const ForumThreadBadgeTheme({
    required this.closed,
    required this.digest,
    required this.sticky,
    required this.standard,
  });

  factory ForumThreadBadgeTheme.fromColorScheme(
    ColorScheme scheme, {
    Color? standardBackground,
    Color? standardForeground,
  }) {
    return ForumThreadBadgeTheme(
      closed: ForumThreadBadgeColors(
        background: scheme.error,
        foreground: scheme.onError,
      ),
      digest: ForumThreadBadgeColors(
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
      ),
      sticky: ForumThreadBadgeColors(
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
      ),
      standard: ForumThreadBadgeColors(
        background: standardBackground ?? scheme.primary,
        foreground: standardForeground ?? scheme.onPrimary,
      ),
    );
  }

  final ForumThreadBadgeColors closed;
  final ForumThreadBadgeColors digest;
  final ForumThreadBadgeColors sticky;
  final ForumThreadBadgeColors standard;

  @override
  ForumThreadBadgeTheme copyWith({
    ForumThreadBadgeColors? closed,
    ForumThreadBadgeColors? digest,
    ForumThreadBadgeColors? sticky,
    ForumThreadBadgeColors? standard,
  }) {
    return ForumThreadBadgeTheme(
      closed: closed ?? this.closed,
      digest: digest ?? this.digest,
      sticky: sticky ?? this.sticky,
      standard: standard ?? this.standard,
    );
  }

  @override
  ForumThreadBadgeTheme lerp(
    ThemeExtension<ForumThreadBadgeTheme>? other,
    double t,
  ) {
    if (other is! ForumThreadBadgeTheme) return this;
    return ForumThreadBadgeTheme(
      closed: closed.lerp(other.closed, t),
      digest: digest.lerp(other.digest, t),
      sticky: sticky.lerp(other.sticky, t),
      standard: standard.lerp(other.standard, t),
    );
  }
}
