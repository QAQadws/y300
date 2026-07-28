import 'package:y300/features/library_shared/domain/models/library_models.dart';

/// Recognizes only application-generated title fallbacks from older releases.
/// Server and user titles that do not match these exact shapes remain raw.
abstract final class LibraryTitleFallbackPolicy {
  static const Set<String> _legacyComicTitles = <String>{'未命名漫画', '未命名漫畫'};
  static const Set<String> _legacyNovelTitles = <String>{'未命名小说', '未命名小說'};
  static const Set<String> _legacyChapterTitles = <String>{'未命名章节', '未命名章節'};

  static bool needsWorkFallback(LibraryModuleKey moduleKey, String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty) {
      return moduleKey != LibraryModuleKey.favorite;
    }
    return switch (moduleKey) {
      LibraryModuleKey.comic => _legacyComicTitles.contains(title),
      LibraryModuleKey.novel => _legacyNovelTitles.contains(title),
      LibraryModuleKey.favorite => false,
    };
  }

  static bool needsChapterFallback(String rawTitle, String? sourceTid) {
    final title = rawTitle.trim();
    if (title.isEmpty || _legacyChapterTitles.contains(title)) {
      return true;
    }
    final tid = sourceTid?.trim() ?? '';
    if (tid.isEmpty) {
      return false;
    }
    return title == tid || title == '章节 $tid' || title == '章節 $tid';
  }
}
