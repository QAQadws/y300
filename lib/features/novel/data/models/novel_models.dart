import 'package:y300/features/novel/domain/models/novel_source_models.dart';

class NovelItem {
  const NovelItem({
    required this.novelId,
    required this.sourceTid,
    required this.sourceFid,
    this.sourceTypeId,
    this.sourceTagName,
    required this.title,
    this.author,
    this.customTitle,
    this.coverImageUrl,
    this.coverLocalPath,
    this.customCoverLocalPath,
    this.customCoverFocusX,
    this.customCoverFocusY,
    required this.updatedAt,
    required this.episodeCount,
    this.categoryId = 'default',
  });

  final String novelId;
  final String sourceTid;
  final String sourceFid;
  final String? sourceTypeId;
  final String? sourceTagName;
  final String title;

  /// 来源发布者名称；小说详情不额外维护作品作者或翻译者。
  final String? author;
  final String? customTitle;
  final String? coverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final double? customCoverFocusX;
  final double? customCoverFocusY;
  final DateTime updatedAt;
  final int episodeCount;
  final String categoryId;

  String get sourceTitle => title;

  String get displayTitle =>
      _preferredText(customTitle, sourceTitle) ?? sourceTitle;

  String? get publisherName => _preferredText(author, null);
}

String? _preferredText(String? preferred, String? fallback) {
  final normalizedPreferred = preferred?.trim();
  if (normalizedPreferred != null && normalizedPreferred.isNotEmpty) {
    return normalizedPreferred;
  }
  final normalizedFallback = fallback?.trim();
  return normalizedFallback == null || normalizedFallback.isEmpty
      ? null
      : normalizedFallback;
}

class NovelEpisodeItem {
  const NovelEpisodeItem({
    required this.episodeId,
    required this.novelId,
    required this.sourceTid,
    this.sourcePid,
    this.sourcePage,
    required this.episodeTitle,
    required this.orderIndex,
    this.datelineText,
  });

  final String episodeId;
  final String novelId;
  final String sourceTid;
  final String? sourcePid;
  final int? sourcePage;
  final String episodeTitle;
  final int orderIndex;
  final String? datelineText;
}

class NovelChapterContent {
  const NovelChapterContent({
    required this.episodeId,
    required this.rawHtml,
    required this.plainText,
    required this.paragraphs,
  });

  final String episodeId;
  final String rawHtml;
  final String plainText;
  final List<String> paragraphs;
}

enum NovelReaderThemePreset { light, sepia, dark, followSystem }

enum NovelReaderFlowMode { vertical, pagedLtr, pagedRtl }

enum NovelReaderTextAlignMode { start, justify, center }

/// Traditional/simplified conversion direction for the novel reader.
/// Stored alongside other reader preferences; maps to the shared
/// [TextConversionMode] via [NovelReaderConversionModeCodec].
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
      default:
        return NovelReaderThemePreset.light;
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
    NovelReaderThemePreset themePreset = NovelReaderThemePreset.light,
    this.contentMaxWidth = 720,
    this.firstLineIndent = 0,
    this.fontWeight = 400,
    this.textAlign = NovelReaderTextAlignMode.start,
    this.showProgressIndicator = true,
    this.showChapterTitle = true,
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
    required this.showChapterTitle,
    required this.conversionMode,
  });

  factory NovelReaderPreferences.defaults() {
    return const NovelReaderPreferences._(
      fontSize: 18,
      lineHeight: 1.8,
      paragraphSpacing: 10,
      pagePadding: 16,
      fontFamily: 'system',
      flowMode: NovelReaderFlowMode.vertical,
      themePreset: NovelReaderThemePreset.light,
      contentMaxWidth: 720,
      firstLineIndent: 0,
      fontWeight: 400,
      textAlign: NovelReaderTextAlignMode.start,
      showProgressIndicator: true,
      showChapterTitle: true,
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
  final bool showChapterTitle;
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
        other.showChapterTitle == showChapterTitle &&
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
    showChapterTitle,
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
    bool? showChapterTitle,
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
      showChapterTitle: showChapterTitle ?? this.showChapterTitle,
      conversionMode: conversionMode ?? this.conversionMode,
    );
  }
}

class NovelReadingProgress {
  const NovelReadingProgress({
    required this.novelId,
    required this.episodeId,
    required this.scrollOffset,
    required this.updatedAt,
    this.flowMode = NovelReaderFlowMode.vertical,
    this.pageIndex = 0,
    this.anchorNodeId,
    this.progressPercent = 0,
  });

  final String novelId;
  final String episodeId;
  final double scrollOffset;
  final DateTime updatedAt;
  final NovelReaderFlowMode flowMode;
  final int pageIndex;
  final String? anchorNodeId;
  final double progressPercent;
}

class NovelEpisodeRefreshResult {
  const NovelEpisodeRefreshResult({
    required this.insertedCount,
    required this.updatedCount,
    required this.totalCount,
  });

  final int insertedCount;
  final int updatedCount;
  final int totalCount;
}

class NovelRefreshSeed extends NovelSourceSeed {
  const NovelRefreshSeed({
    required super.fid,
    required super.tid,
    super.typeid,
    super.tagName,
  });
}

class NovelShelfCategory {
  const NovelShelfCategory({
    required this.categoryId,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
  });

  final String categoryId;
  final String name;
  final int sortOrder;
  final DateTime createdAt;

  bool get isDefault => categoryId == 'default';
}
