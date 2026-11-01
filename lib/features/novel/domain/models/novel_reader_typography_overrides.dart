/// Reader requests, independent of Flutter style types and storage payloads.
enum NovelReaderStyleScope { asDefault, forceBody, forceAll }

enum NovelReaderIndentUnit { logicalPixels, em }

typedef NovelReaderEffectiveIndent = ({
  double value,
  NovelReaderIndentUnit unit,
  NovelReaderStyleScope scope,
});

final class NovelReaderFirstLineIndent {
  const NovelReaderFirstLineIndent({
    required this.em,
    this.scope = NovelReaderStyleScope.forceBody,
  });
  const NovelReaderFirstLineIndent.followAuthor()
    : em = 0,
      scope = NovelReaderStyleScope.asDefault;

  static const minimumEm = 0.0;
  static const maximumEm = 4.0;
  static const stepEm = .25;
  static const initialEm = 2.0;
  final double em;
  final NovelReaderStyleScope scope;
  bool get isValid => em.isFinite && em >= minimumEm && em <= maximumEm;

  @override
  bool operator ==(Object other) =>
      other is NovelReaderFirstLineIndent &&
      other.em == em &&
      other.scope == scope;
  @override
  int get hashCode => Object.hash(em, scope);
}

/// Native letter spacing in logical pixels, independent of word spacing.
final class NovelReaderLetterSpacing {
  const NovelReaderLetterSpacing({
    required this.logicalPixels,
    this.scope = NovelReaderStyleScope.forceBody,
  });
  static const minimum = -2.0;
  static const maximum = 8.0;
  static const step = .25;
  final double logicalPixels;
  final NovelReaderStyleScope scope;
  bool get isValid =>
      logicalPixels.isFinite &&
      logicalPixels >= minimum &&
      logicalPixels <= maximum;

  @override
  bool operator ==(Object other) =>
      other is NovelReaderLetterSpacing &&
      other.logicalPixels == logicalPixels &&
      other.scope == scope;
  @override
  int get hashCode => Object.hash(logicalPixels, scope);
}

/// Native word spacing in logical pixels; it does not replace letter spacing.
final class NovelReaderWordSpacing {
  const NovelReaderWordSpacing({
    required this.logicalPixels,
    this.scope = NovelReaderStyleScope.forceBody,
  });
  static const minimum = -2.0;
  static const maximum = 16.0;
  static const step = .25;
  final double logicalPixels;
  final NovelReaderStyleScope scope;
  bool get isValid =>
      logicalPixels.isFinite &&
      logicalPixels >= minimum &&
      logicalPixels <= maximum;
  @override
  bool operator ==(Object other) =>
      other is NovelReaderWordSpacing &&
      other.logicalPixels == logicalPixels &&
      other.scope == scope;
  @override
  int get hashCode => Object.hash(logicalPixels, scope);
}

/// Logical pixel margins, collapsed by the renderer rather than added together.
final class NovelReaderParagraphSpacing {
  const NovelReaderParagraphSpacing({
    required this.before,
    required this.after,
    this.scope = NovelReaderStyleScope.forceBody,
  });
  static const minimum = 0.0;
  static const maximum = 64.0;
  static const step = 1.0;
  final double before;
  final double after;
  final NovelReaderStyleScope scope;
  bool get isValid =>
      before.isFinite &&
      before >= minimum &&
      before <= maximum &&
      after.isFinite &&
      after >= minimum &&
      after <= maximum;

  @override
  bool operator ==(Object other) =>
      other is NovelReaderParagraphSpacing &&
      other.before == before &&
      other.after == after &&
      other.scope == scope;
  @override
  int get hashCode => Object.hash(before, after, scope);
}

/// Sparse requests. Absence inherits the preceding scope; explicit author/zero
/// values remain distinct so a later work override can undo a global setting.
final class NovelReaderTypographyOverrides {
  const NovelReaderTypographyOverrides({
    this.firstLineIndent,
    this.paragraphSpacing,
    this.letterSpacing,
    this.wordSpacing,
    this.fontSizeScope,
  });
  final NovelReaderFirstLineIndent? firstLineIndent;
  final NovelReaderParagraphSpacing? paragraphSpacing;
  final NovelReaderLetterSpacing? letterSpacing;
  final NovelReaderWordSpacing? wordSpacing;

  /// Null inherits the preceding scope; asDefault explicitly keeps author sizes.
  final NovelReaderStyleScope? fontSizeScope;
  bool get isEmpty =>
      firstLineIndent == null &&
      paragraphSpacing == null &&
      letterSpacing == null &&
      wordSpacing == null &&
      fontSizeScope == null;

  NovelReaderTypographyOverrides withFirstLineIndent(
    NovelReaderFirstLineIndent? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: value,
    paragraphSpacing: paragraphSpacing,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    fontSizeScope: fontSizeScope,
  );

  NovelReaderTypographyOverrides withParagraphSpacing(
    NovelReaderParagraphSpacing? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: firstLineIndent,
    paragraphSpacing: value,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    fontSizeScope: fontSizeScope,
  );

  NovelReaderTypographyOverrides withLetterSpacing(
    NovelReaderLetterSpacing? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: firstLineIndent,
    paragraphSpacing: paragraphSpacing,
    letterSpacing: value,
    wordSpacing: wordSpacing,
    fontSizeScope: fontSizeScope,
  );

  NovelReaderTypographyOverrides withWordSpacing(
    NovelReaderWordSpacing? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: firstLineIndent,
    paragraphSpacing: paragraphSpacing,
    letterSpacing: letterSpacing,
    wordSpacing: value,
    fontSizeScope: fontSizeScope,
  );

  NovelReaderTypographyOverrides withFontSizeScope(
    NovelReaderStyleScope? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: firstLineIndent,
    paragraphSpacing: paragraphSpacing,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    fontSizeScope: value,
  );

  NovelReaderTypographyOverrides over(NovelReaderTypographyOverrides base) =>
      NovelReaderTypographyOverrides(
        firstLineIndent: firstLineIndent ?? base.firstLineIndent,
        paragraphSpacing: paragraphSpacing ?? base.paragraphSpacing,
        letterSpacing: letterSpacing ?? base.letterSpacing,
        wordSpacing: wordSpacing ?? base.wordSpacing,
        fontSizeScope: fontSizeScope ?? base.fontSizeScope,
      );

  @override
  bool operator ==(Object other) =>
      other is NovelReaderTypographyOverrides &&
      other.firstLineIndent == firstLineIndent &&
      other.paragraphSpacing == paragraphSpacing &&
      other.letterSpacing == letterSpacing &&
      other.wordSpacing == wordSpacing &&
      other.fontSizeScope == fontSizeScope;
  @override
  int get hashCode => Object.hash(
    firstLineIndent,
    paragraphSpacing,
    letterSpacing,
    wordSpacing,
    fontSizeScope,
  );
}
