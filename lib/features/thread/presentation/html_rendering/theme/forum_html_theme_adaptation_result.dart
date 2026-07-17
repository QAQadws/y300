import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as html_dom;

final class ForumHtmlThemeAdaptationResult {
  const ForumHtmlThemeAdaptationResult({
    required this.fragment,
    required this.stats,
  });

  final html_dom.DocumentFragment fragment;
  final ForumHtmlThemeAdaptationStats stats;
}

@immutable
final class ForumHtmlThemeAdaptationStats {
  const ForumHtmlThemeAdaptationStats({
    required this.explicitForegroundCount,
    required this.remappedForegroundCount,
    required this.explicitBackgroundCount,
    required this.remappedBackgroundCount,
    required this.semanticFallbackCount,
    required this.unsupportedColorCount,
    required this.concealedTextRangeCount,
    required this.minimumResultContrast,
  });

  static const none = ForumHtmlThemeAdaptationStats(
    explicitForegroundCount: 0,
    remappedForegroundCount: 0,
    explicitBackgroundCount: 0,
    remappedBackgroundCount: 0,
    semanticFallbackCount: 0,
    unsupportedColorCount: 0,
    concealedTextRangeCount: 0,
    minimumResultContrast: null,
  );

  final int explicitForegroundCount;
  final int remappedForegroundCount;
  final int explicitBackgroundCount;
  final int remappedBackgroundCount;
  final int semanticFallbackCount;
  final int unsupportedColorCount;
  final int concealedTextRangeCount;
  final double? minimumResultContrast;
}
