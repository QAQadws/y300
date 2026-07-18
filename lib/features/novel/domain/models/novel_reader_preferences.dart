enum NovelReaderThemePreset { light, sepia, dark, followSystem }

enum NovelReaderFlowMode { vertical, pagedLtr, pagedRtl }

enum NovelReaderTextAlignMode { start, justify, center }

/// Traditional/simplified conversion direction for the novel reader.
enum NovelReaderConversionMode { none, toSimplified, toTraditional }

extension NovelReaderConversionModeCodec on NovelReaderConversionMode {
  String get storageValue {
    switch (this) {
      case NovelReaderConversionMode.none:
        return 'none';
      case NovelReaderConversionMode.toSimplified:
        return 'toSimplified';
      case NovelReaderConversionMode.toTraditional:
        return 'toTraditional';
    }
  }

  static NovelReaderConversionMode fromStorage(String? value) {
    switch (value) {
      case 'toSimplified':
        return NovelReaderConversionMode.toSimplified;
      case 'toTraditional':
        return NovelReaderConversionMode.toTraditional;
      case 'none':
      default:
        return NovelReaderConversionMode.none;
    }
  }
}

extension NovelReaderThemePresetCodec on NovelReaderThemePreset {
  String get storageValue {
    switch (this) {
      case NovelReaderThemePreset.light:
        return 'light';
      case NovelReaderThemePreset.sepia:
        return 'sepia';
      case NovelReaderThemePreset.dark:
        return 'dark';
      case NovelReaderThemePreset.followSystem:
        return 'followSystem';
    }
  }

  static NovelReaderThemePreset fromStorage(String? value) {
    switch (value) {
      case 'sepia':
        return NovelReaderThemePreset.sepia;
      case 'dark':
        return NovelReaderThemePreset.dark;
      case 'followSystem':
      case 'follow_system':
      case 'system':
        return NovelReaderThemePreset.followSystem;
      case 'light':
        return NovelReaderThemePreset.light;
      default:
        return NovelReaderThemePreset.sepia;
    }
  }
}

extension NovelReaderFlowModeCodec on NovelReaderFlowMode {
  String get storageValue {
    switch (this) {
      case NovelReaderFlowMode.vertical:
        return 'vertical';
      case NovelReaderFlowMode.pagedLtr:
        return 'pagedLtr';
      case NovelReaderFlowMode.pagedRtl:
        return 'pagedRtl';
    }
  }

  static NovelReaderFlowMode fromStorage(String? value) {
    switch (value) {
      case 'pagedLtr':
      case 'paged_ltr':
        return NovelReaderFlowMode.pagedLtr;
      case 'pagedRtl':
      case 'paged_rtl':
        return NovelReaderFlowMode.pagedRtl;
      case 'vertical':
      default:
        return NovelReaderFlowMode.vertical;
    }
  }
}

extension NovelReaderTextAlignModeCodec on NovelReaderTextAlignMode {
  String get storageValue {
    switch (this) {
      case NovelReaderTextAlignMode.start:
        return 'start';
      case NovelReaderTextAlignMode.justify:
        return 'justify';
      case NovelReaderTextAlignMode.center:
        return 'center';
    }
  }

  static NovelReaderTextAlignMode fromStorage(String? value) {
    switch (value) {
      case 'justify':
        return NovelReaderTextAlignMode.justify;
      case 'center':
        return NovelReaderTextAlignMode.center;
      case 'start':
      default:
        return NovelReaderTextAlignMode.start;
    }
  }
}

class NovelReaderPreferences {
  NovelReaderPreferences({
    required this.fontSize,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.pagePadding,
    required this.fontFamily,
    this.flowMode = NovelReaderFlowMode.vertical,
    NovelReaderThemePreset themePreset = NovelReaderThemePreset.sepia,
    this.contentMaxWidth = 720,
    this.firstLineIndent = 0,
    this.fontWeight = 400,
    this.textAlign = NovelReaderTextAlignMode.start,
    this.showProgressIndicator = true,
    this.conversionMode = NovelReaderConversionMode.none,
    String? themeMode,
  }) : themePreset = themeMode == null
           ? themePreset
           : NovelReaderThemePresetCodec.fromStorage(themeMode);

  const NovelReaderPreferences._({
    required this.fontSize,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.pagePadding,
    required this.fontFamily,
    required this.flowMode,
    required this.themePreset,
    required this.contentMaxWidth,
    required this.firstLineIndent,
    required this.fontWeight,
    required this.textAlign,
    required this.showProgressIndicator,
    required this.conversionMode,
  });

  factory NovelReaderPreferences.defaults() {
    return const NovelReaderPreferences._(
      fontSize: 18.5,
      lineHeight: 1.6,
      paragraphSpacing: 10,
      pagePadding: 16,
      fontFamily: 'system',
      flowMode: NovelReaderFlowMode.vertical,
      themePreset: NovelReaderThemePreset.sepia,
      contentMaxWidth: 720,
      firstLineIndent: 0,
      fontWeight: 400,
      textAlign: NovelReaderTextAlignMode.start,
      showProgressIndicator: true,
      conversionMode: NovelReaderConversionMode.none,
    );
  }

  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final double pagePadding;
  final String fontFamily;
  final NovelReaderFlowMode flowMode;
  final NovelReaderThemePreset themePreset;
  final double contentMaxWidth;
  final double firstLineIndent;
  final int fontWeight;
  final NovelReaderTextAlignMode textAlign;
  final bool showProgressIndicator;
  final NovelReaderConversionMode conversionMode;

  String get themeMode => themePreset.storageValue;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is NovelReaderPreferences &&
        other.fontSize == fontSize &&
        other.lineHeight == lineHeight &&
        other.paragraphSpacing == paragraphSpacing &&
        other.pagePadding == pagePadding &&
        other.fontFamily == fontFamily &&
        other.flowMode == flowMode &&
        other.themePreset == themePreset &&
        other.contentMaxWidth == contentMaxWidth &&
        other.firstLineIndent == firstLineIndent &&
        other.fontWeight == fontWeight &&
        other.textAlign == textAlign &&
        other.showProgressIndicator == showProgressIndicator &&
        other.conversionMode == conversionMode;
  }

  @override
  int get hashCode => Object.hash(
    fontSize,
    lineHeight,
    paragraphSpacing,
    pagePadding,
    fontFamily,
    flowMode,
    themePreset,
    contentMaxWidth,
    firstLineIndent,
    fontWeight,
    textAlign,
    showProgressIndicator,
    conversionMode,
  );

  NovelReaderPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? pagePadding,
    String? themeMode,
    String? fontFamily,
    NovelReaderFlowMode? flowMode,
    NovelReaderThemePreset? themePreset,
    double? contentMaxWidth,
    double? firstLineIndent,
    int? fontWeight,
    NovelReaderTextAlignMode? textAlign,
    bool? showProgressIndicator,
    NovelReaderConversionMode? conversionMode,
  }) {
    return NovelReaderPreferences._(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      pagePadding: pagePadding ?? this.pagePadding,
      fontFamily: fontFamily ?? this.fontFamily,
      flowMode: flowMode ?? this.flowMode,
      themePreset: themeMode == null
          ? (themePreset ?? this.themePreset)
          : NovelReaderThemePresetCodec.fromStorage(themeMode),
      contentMaxWidth: contentMaxWidth ?? this.contentMaxWidth,
      firstLineIndent: firstLineIndent ?? this.firstLineIndent,
      fontWeight: fontWeight ?? this.fontWeight,
      textAlign: textAlign ?? this.textAlign,
      showProgressIndicator:
          showProgressIndicator ?? this.showProgressIndicator,
      conversionMode: conversionMode ?? this.conversionMode,
    );
  }
}
