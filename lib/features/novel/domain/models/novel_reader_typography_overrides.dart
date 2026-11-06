/// Reader requests, independent of Flutter style types and storage payloads.
enum NovelReaderStyleScope { asDefault, forceBody, forceAll }

/// Logical alignment follows paragraph direction, not page-turn direction.
enum NovelReaderTextAlignMode { start, justify, center, end }

final class NovelReaderTextAlignment {
  const NovelReaderTextAlignment({
    required this.mode,
    this.scope = NovelReaderStyleScope.forceBody,
  });
  final NovelReaderTextAlignMode mode;
  final NovelReaderStyleScope scope;
  @override
  bool operator ==(Object other) =>
      other is NovelReaderTextAlignment &&
      other.mode == mode &&
      other.scope == scope;
  @override
  int get hashCode => Object.hash(mode, scope);
}

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

/// Requested base weight, not a claim about the face selected by the engine.
/// Reserve 900 for emphasis so strong text can remain heavier than the body.
final class NovelReaderFontWeight {
  const NovelReaderFontWeight({
    required this.value,
    this.scope = NovelReaderStyleScope.forceBody,
  });
  static const minimum = 100;
  static const maximum = 800;
  static const step = 100;
  static const initial = 400;
  final int value;
  final NovelReaderStyleScope scope;
  bool get isValid => value >= minimum && value <= maximum && value % step == 0;

  @override
  bool operator ==(Object other) =>
      other is NovelReaderFontWeight &&
      other.value == value &&
      other.scope == scope;
  @override
  int get hashCode => Object.hash(value, scope);
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

/// A missing percentage inherits; 100 explicitly restores the role's base size.
final class NovelReaderRoleFontSizes {
  const NovelReaderRoleFontSizes({this.heading, this.quote, this.code});

  static const minimum = 75;
  static const maximum = 150;
  static const step = 5;
  static const defaultPercent = 100;
  final int? heading;
  final int? quote;
  final int? code;

  static int? validPercent(Object? value) =>
      value is int &&
          value >= minimum &&
          value <= maximum &&
          (value - minimum) % step == 0
      ? value
      : null;

  bool get isEmpty => heading == null && quote == null && code == null;

  NovelReaderRoleFontSizes over(NovelReaderRoleFontSizes base) =>
      NovelReaderRoleFontSizes(
        heading: heading ?? base.heading,
        quote: quote ?? base.quote,
        code: code ?? base.code,
      );

  @override
  bool operator ==(Object other) =>
      other is NovelReaderRoleFontSizes &&
      other.heading == heading &&
      other.quote == quote &&
      other.code == code;

  @override
  int get hashCode => Object.hash(heading, quote, code);
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
    this.lineHeightScope,
    this.fontWeight,
    this.textAlignment,
    this.roleFontSizes = const NovelReaderRoleFontSizes(),
  });
  final NovelReaderFirstLineIndent? firstLineIndent;
  final NovelReaderParagraphSpacing? paragraphSpacing;
  final NovelReaderLetterSpacing? letterSpacing;
  final NovelReaderWordSpacing? wordSpacing;
  final NovelReaderFontWeight? fontWeight;
  final NovelReaderTextAlignment? textAlignment;
  final NovelReaderRoleFontSizes roleFontSizes;

  /// Null inherits the preceding scope; asDefault explicitly keeps author sizes.
  final NovelReaderStyleScope? fontSizeScope;

  /// Uses the existing reader line-height factor; no second numeric value.
  final NovelReaderStyleScope? lineHeightScope;
  bool get isEmpty =>
      firstLineIndent == null &&
      paragraphSpacing == null &&
      letterSpacing == null &&
      wordSpacing == null &&
      fontSizeScope == null &&
      lineHeightScope == null &&
      fontWeight == null &&
      textAlignment == null &&
      roleFontSizes.isEmpty;

  NovelReaderTypographyOverrides withFirstLineIndent(
    NovelReaderFirstLineIndent? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: value,
    textAlignment: textAlignment,
    roleFontSizes: roleFontSizes,
    fontWeight: fontWeight,
    paragraphSpacing: paragraphSpacing,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    fontSizeScope: fontSizeScope,
    lineHeightScope: lineHeightScope,
  );

  NovelReaderTypographyOverrides withParagraphSpacing(
    NovelReaderParagraphSpacing? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: firstLineIndent,
    paragraphSpacing: value,
    textAlignment: textAlignment,
    roleFontSizes: roleFontSizes,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    fontSizeScope: fontSizeScope,
    lineHeightScope: lineHeightScope,
  );

  NovelReaderTypographyOverrides withLetterSpacing(
    NovelReaderLetterSpacing? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: firstLineIndent,
    paragraphSpacing: paragraphSpacing,
    letterSpacing: value,
    textAlignment: textAlignment,
    roleFontSizes: roleFontSizes,
    fontWeight: fontWeight,
    wordSpacing: wordSpacing,
    fontSizeScope: fontSizeScope,
    lineHeightScope: lineHeightScope,
  );

  NovelReaderTypographyOverrides withWordSpacing(
    NovelReaderWordSpacing? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: firstLineIndent,
    paragraphSpacing: paragraphSpacing,
    letterSpacing: letterSpacing,
    wordSpacing: value,
    textAlignment: textAlignment,
    roleFontSizes: roleFontSizes,
    fontWeight: fontWeight,
    fontSizeScope: fontSizeScope,
    lineHeightScope: lineHeightScope,
  );

  NovelReaderTypographyOverrides withFontSizeScope(
    NovelReaderStyleScope? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: firstLineIndent,
    paragraphSpacing: paragraphSpacing,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    fontSizeScope: value,
    textAlignment: textAlignment,
    roleFontSizes: roleFontSizes,
    fontWeight: fontWeight,
    lineHeightScope: lineHeightScope,
  );

  NovelReaderTypographyOverrides withLineHeightScope(
    NovelReaderStyleScope? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: firstLineIndent,
    paragraphSpacing: paragraphSpacing,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    fontSizeScope: fontSizeScope,
    lineHeightScope: value,
    textAlignment: textAlignment,
    roleFontSizes: roleFontSizes,
    fontWeight: fontWeight,
  );

  NovelReaderTypographyOverrides withFontWeight(NovelReaderFontWeight? value) =>
      NovelReaderTypographyOverrides(
        firstLineIndent: firstLineIndent,
        paragraphSpacing: paragraphSpacing,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        fontSizeScope: fontSizeScope,
        lineHeightScope: lineHeightScope,
        fontWeight: value,
        textAlignment: textAlignment,
        roleFontSizes: roleFontSizes,
      );

  NovelReaderTypographyOverrides withTextAlignment(
    NovelReaderTextAlignment? value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: firstLineIndent,
    paragraphSpacing: paragraphSpacing,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    fontSizeScope: fontSizeScope,
    lineHeightScope: lineHeightScope,
    fontWeight: fontWeight,
    textAlignment: value,
    roleFontSizes: roleFontSizes,
  );

  NovelReaderTypographyOverrides withRoleFontSizes(
    NovelReaderRoleFontSizes value,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: firstLineIndent,
    paragraphSpacing: paragraphSpacing,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    fontSizeScope: fontSizeScope,
    lineHeightScope: lineHeightScope,
    fontWeight: fontWeight,
    textAlignment: textAlignment,
    roleFontSizes: value,
  );

  NovelReaderTypographyOverrides over(NovelReaderTypographyOverrides base) =>
      NovelReaderTypographyOverrides(
        firstLineIndent: firstLineIndent ?? base.firstLineIndent,
        paragraphSpacing: paragraphSpacing ?? base.paragraphSpacing,
        letterSpacing: letterSpacing ?? base.letterSpacing,
        wordSpacing: wordSpacing ?? base.wordSpacing,
        fontSizeScope: fontSizeScope ?? base.fontSizeScope,
        lineHeightScope: lineHeightScope ?? base.lineHeightScope,
        fontWeight: fontWeight ?? base.fontWeight,
        textAlignment: textAlignment ?? base.textAlignment,
        roleFontSizes: roleFontSizes.over(base.roleFontSizes),
      );

  @override
  bool operator ==(Object other) =>
      other is NovelReaderTypographyOverrides &&
      other.firstLineIndent == firstLineIndent &&
      other.paragraphSpacing == paragraphSpacing &&
      other.letterSpacing == letterSpacing &&
      other.wordSpacing == wordSpacing &&
      other.fontSizeScope == fontSizeScope &&
      other.lineHeightScope == lineHeightScope &&
      other.fontWeight == fontWeight &&
      other.textAlignment == textAlignment &&
      other.roleFontSizes == roleFontSizes;
  @override
  int get hashCode => Object.hash(
    firstLineIndent,
    paragraphSpacing,
    letterSpacing,
    wordSpacing,
    fontSizeScope,
    lineHeightScope,
    fontWeight,
    textAlignment,
    roleFontSizes,
  );
}
