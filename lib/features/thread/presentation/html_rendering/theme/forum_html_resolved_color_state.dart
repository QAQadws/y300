import 'dart:ui';

import 'package:flutter/foundation.dart';

enum ForumHtmlSemanticColorRole {
  body,
  link,
  quote,
  code,
  editStatus,
  concealedText,
}

@immutable
final class ForumHtmlResolvedColorState {
  const ForumHtmlResolvedColorState({
    required this.effectiveForeground,
    required this.effectiveBackground,
    required this.semanticRole,
  });

  final Color effectiveForeground;
  final Color effectiveBackground;
  final ForumHtmlSemanticColorRole semanticRole;
}
