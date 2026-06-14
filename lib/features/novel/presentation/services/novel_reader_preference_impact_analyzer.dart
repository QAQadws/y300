import 'package:y300/features/novel/data/models/novel_models.dart';

enum NovelReaderPreferenceImpact {
  none,
  repaintOnly,
  relayout,
  flowModeSwitch,
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
        impacts: const <NovelReaderPreferenceImpact>{NovelReaderPreferenceImpact.none},
      );
    }

    final impacts = <NovelReaderPreferenceImpact>{};
    if (previous.flowMode != next.flowMode) {
      impacts.add(NovelReaderPreferenceImpact.flowModeSwitch);
    }
    if (previous.themePreset != next.themePreset ||
        previous.showProgressIndicator != next.showProgressIndicator) {
      impacts.add(NovelReaderPreferenceImpact.repaintOnly);
    }
    if (previous.fontSize != next.fontSize ||
        previous.lineHeight != next.lineHeight ||
        previous.paragraphSpacing != next.paragraphSpacing ||
        previous.pagePadding != next.pagePadding ||
        previous.fontFamily != next.fontFamily ||
        previous.contentMaxWidth != next.contentMaxWidth ||
        previous.firstLineIndent != next.firstLineIndent ||
        previous.fontWeight != next.fontWeight ||
        previous.textAlign != next.textAlign ||
        previous.showChapterTitle != next.showChapterTitle) {
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
