enum ForumBodyRubySide { over, under }

/// Inherited CSS value. Resolving a side belongs to annotation-level pairing,
/// not to each RT child: an alternate level depends on the preceding level.
enum ForumBodyRubyPosition {
  alternate,
  alternateOver,
  alternateUnder,
  over,
  under,
  interCharacter;

  static ForumBodyRubyPosition? tryParse(String value) {
    final words = value.trim().toLowerCase().split(RegExp(r'\s+'));
    if (words.length == 1) {
      return switch (words.single) {
        'alternate' => alternate,
        'over' => over,
        'under' => under,
        'inter-character' => interCharacter,
        _ => null,
      };
    }
    if (words.length == 2 && words.contains('alternate')) {
      if (words.contains('over')) return alternateOver;
      if (words.contains('under')) return alternateUnder;
    }
    return null;
  }

  /// Null requires the separate inter-character/vertical layout backend.
  ForumBodyRubySide? sideAfter(ForumBodyRubySide? previous) => switch (this) {
    over => ForumBodyRubySide.over,
    under => ForumBodyRubySide.under,
    interCharacter => null,
    alternate || alternateOver || alternateUnder =>
      previous == null
          ? this == alternateUnder
                ? ForumBodyRubySide.under
                : ForumBodyRubySide.over
          : previous == ForumBodyRubySide.over
          ? ForumBodyRubySide.under
          : ForumBodyRubySide.over,
  };
}
