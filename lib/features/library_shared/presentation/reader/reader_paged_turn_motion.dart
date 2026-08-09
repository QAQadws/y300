import 'package:flutter/material.dart';

/// Shared motion contract for programmatic page turns in paged readers.
abstract final class ReaderPagedTurnMotion {
  static const Duration tapConfirmationDelay = Duration(milliseconds: 220);
  static const Duration animationDuration = Duration(milliseconds: 160);
  static const Curve animationCurve = Curves.easeOutCubic;
}
