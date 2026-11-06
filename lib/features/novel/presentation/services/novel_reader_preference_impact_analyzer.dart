import 'package:y300/features/novel/data/models/novel_models.dart';

enum NovelReaderPreferenceImpact {
  none,
  repaintOnly,
  relayout,
  flowModeSwitch,

  /// The source document must be re-parsed/re-built (e.g. traditional/
  /// simplified conversion changed). Most expensive impact.
  contentRebuild,
}

class NovelReaderPreferenceDiff {
  const NovelReaderPreferenceDiff({
    required this.previous,
    required this.next,
    required this.impacts,
  });

  final NovelReaderPreferences previous;
  final NovelReaderPreferences next;
  final Set<NovelReaderPreferenceImpact> impacts;

  bool get hasChanges => previous != next;
}

abstract interface class NovelReaderPreferenceImpactAnalyzer {
  NovelReaderPreferenceDiff compare(
    NovelReaderPreferences previous,
    NovelReaderPreferences next,
  );
}

class DefaultNovelReaderPreferenceImpactAnalyzer
    implements NovelReaderPreferenceImpactAnalyzer {
  const DefaultNovelReaderPreferenceImpactAnalyzer();

  @override
  NovelReaderPreferenceDiff compare(
    NovelReaderPreferences previous,
    NovelReaderPreferences next,
  ) {
    if (previous == next) {
      return NovelReaderPreferenceDiff(
        previous: previous,
        next: next,
        impacts: const <NovelReaderPreferenceImpact>{
          NovelReaderPreferenceImpact.none,
        },
      );
    }

    final impacts = <NovelReaderPreferenceImpact>{};
    if (previous.conversionMode != next.conversionMode) {
      impacts.add(NovelReaderPreferenceImpact.contentRebuild);
    }
    if (previous.flowMode != next.flowMode) {
      impacts.add(NovelReaderPreferenceImpact.flowModeSwitch);
    }
    if (previous.themePreset != next.themePreset ||
        previous.colors != next.colors ||
        previous.showProgressIndicator != next.showProgressIndicator) {
      impacts.add(NovelReaderPreferenceImpact.repaintOnly);
    }
    if (previous.fontSize != next.fontSize ||
        previous.viewport != next.viewport ||
        previous.lineHeight != next.lineHeight ||
        previous.effectiveParagraphSpacing != next.effectiveParagraphSpacing ||
        previous.typography.letterSpacing != next.typography.letterSpacing ||
        previous.typography.wordSpacing != next.typography.wordSpacing ||
        previous.typography.fontWeight != next.typography.fontWeight ||
        previous.typography.textAlignment != next.typography.textAlignment ||
        previous.typography.fontSizeScope != next.typography.fontSizeScope ||
        previous.typography.lineHeightScope !=
            next.typography.lineHeightScope ||
        previous.pagePadding != next.pagePadding ||
        previous.fontFamily != next.fontFamily ||
        previous.contentMaxWidth != next.contentMaxWidth ||
        previous.effectiveFirstLineIndent != next.effectiveFirstLineIndent ||
        previous.fontWeight != next.fontWeight ||
        previous.textAlign != next.textAlign ||
        previous.compressBlankLines != next.compressBlankLines ||
        previous.safeAreaEnabled != next.safeAreaEnabled) {
      impacts.add(NovelReaderPreferenceImpact.relayout);
    }
    if (impacts.isEmpty) {
      impacts.add(NovelReaderPreferenceImpact.none);
    }
    return NovelReaderPreferenceDiff(
      previous: previous,
      next: next,
      impacts: impacts,
    );
  }
}
