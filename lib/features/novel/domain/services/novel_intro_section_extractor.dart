import 'package:y300/features/novel/domain/services/novel_chapter_title_candidate_extractor.dart';

/// 从首楼 message 中按"簡介→目录"标记法抽取小说简介。
///
/// 解析规则（与 docs/小说解析流程.md 中的小说 detail 简介需求对齐）：
/// 1. 按 DOM 文档顺序拆成文本单元，同时把 `<br>` 与块级节点作为边界。
/// 2. 找首条匹配 `簡介|介紹|简介|介绍` 的段（"intro 段"）。
/// 3. 找首条匹配 `目录|目錄|电梯|電梯|catalog|contents` 的段（"contents 段"）。
/// 4. 命中模式：
///    - intro 与 contents 都命中且 intro < contents：取 [intro, contents)
///    - 仅 contents 命中：取 [0, contents)
///    - 仅 intro 命中：取 [intro, 结尾]
///    - 其它（都没 / 顺序异常）：返回 null（不更新简介）
///
/// 这是与 [`IntroBeforeFirstChapterRule`] 互补的另一条简介路径：后者
/// 用首章标题之前的文字作为简介；前者用人工目录标记作为边界。
abstract class NovelIntroSectionExtractor {
  const NovelIntroSectionExtractor();

  /// 返回 plain-text 简介，找不到时返回 null。
  String? extract({required String firstPostHtml});
}

class DefaultNovelIntroSectionExtractor implements NovelIntroSectionExtractor {
  const DefaultNovelIntroSectionExtractor({
    NovelChapterTitleCandidateExtractor textUnitExtractor =
        const DiscuzNovelChapterTitleCandidateExtractor(),
    int maxLength = 1200,
  }) : _textUnitExtractor = textUnitExtractor,
       _maxLength = maxLength;

  // 大小写不敏感；冒号、空白由调用方保留。
  static final RegExp _introMarker = RegExp(
    r'(簡介|介紹|简介|介绍)',
    caseSensitive: false,
  );
  static final RegExp _contentsMarker = RegExp(
    r'(目录|目錄|电梯|電梯|catalog|contents)',
    caseSensitive: false,
  );

  final NovelChapterTitleCandidateExtractor _textUnitExtractor;
  final int _maxLength;

  @override
  String? extract({required String firstPostHtml}) {
    if (firstPostHtml.trim().isEmpty) {
      return null;
    }
    // Discuz 首楼经常混用顶层 inline、<br> 和折叠 div。按文档顺序收集
    // 文本单元，不能因页面中存在任意 div 就丢掉 div 外的简介标题与正文。
    final paragraphs = _textUnitExtractor.extractTextUnits(firstPostHtml);
    if (paragraphs.isEmpty) {
      return null;
    }

    final introIdx = _firstParagraphMatching(paragraphs, _introMarker);
    final contentsIdx = _firstParagraphMatching(paragraphs, _contentsMarker);

    final List<String> selected;
    if (introIdx != null && contentsIdx != null && contentsIdx > introIdx) {
      // 上闭下开：包括 intro 段，不包括 contents 段。
      selected = paragraphs.sublist(introIdx, contentsIdx);
    } else if (introIdx == null && contentsIdx != null) {
      // 只有 contents：把目录之前全部当作简介。
      selected = paragraphs.sublist(0, contentsIdx);
    } else if (introIdx != null && contentsIdx == null) {
      // 简介有明确左边界时，缺少目录不应导致整段简介丢失。
      selected = paragraphs.sublist(introIdx);
    } else {
      return null;
    }

    final joined = selected
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .join('\n');
    if (joined.isEmpty) {
      return null;
    }
    return joined.length > _maxLength
        ? joined.substring(0, _maxLength)
        : joined;
  }

  int? _firstParagraphMatching(List<String> paragraphs, RegExp pattern) {
    for (var i = 0; i < paragraphs.length; i++) {
      if (pattern.hasMatch(paragraphs[i])) {
        return i;
      }
    }
    return null;
  }
}
