import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

/// 从首楼 message 中按"簡介→目录"标记法抽取小说简介。
///
/// 解析规则（与 docs/小说解析流程.md 中的小说 detail 简介需求对齐）：
/// 1. 把 message 拆成段落列表（按 `<p>/<div>/<section>/<article>/<li>` 切；
///    没有块级元素时由 [`ForumPostDomExtractor.extractParagraphTexts`] 回退
///    到按换行切分，覆盖 `<br>`/纯文本场景）。
/// 2. 找首条匹配 `簡介|介紹|简介|介绍` 的段（"intro 段"）。
/// 3. 找首条匹配 `目录|目錄|电梯|電梯|catalog|contents` 的段（"contents 段"）。
/// 4. 命中模式：
///    - intro 与 contents 都命中且 intro < contents：取 [intro, contents)
///    - 仅 contents 命中：取 [0, contents)
///    - 其它（仅 intro / 都没 / 顺序异常）：返回 null（不更新简介）
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
    ForumPostDomExtractor domExtractor = const ForumPostDomExtractor(),
    int maxLength = 1200,
  })  : _domExtractor = domExtractor,
        _maxLength = maxLength;

  // 大小写不敏感；冒号、空白由调用方保留。
  static final RegExp _introMarker =
      RegExp(r'(簡介|介紹|简介|介绍)', caseSensitive: false);
  static final RegExp _contentsMarker = RegExp(
    r'(目录|目錄|电梯|電梯|catalog|contents)',
    caseSensitive: false,
  );

  final ForumPostDomExtractor _domExtractor;
  final int _maxLength;

  @override
  String? extract({required String firstPostHtml}) {
    if (firstPostHtml.trim().isEmpty) {
      return null;
    }
    // 关键点：必须按段落（块级元素或回退后的换行）来切，而不是 plain-text
    // —— ForumPostDomExtractor.extractPlainText 不在 <p> 之间插换行。
    final paragraphs = _domExtractor.extractParagraphTexts(firstPostHtml);
    if (paragraphs.isEmpty) {
      return null;
    }

    final introIdx = _firstParagraphMatching(paragraphs, _introMarker);
    final contentsIdx = _firstParagraphMatching(paragraphs, _contentsMarker);

    final List<String> selected;
    if (introIdx != null &&
        contentsIdx != null &&
        contentsIdx > introIdx) {
      // 上闭下开：包括 intro 段，不包括 contents 段。
      selected = paragraphs.sublist(introIdx, contentsIdx);
    } else if (introIdx == null && contentsIdx != null) {
      // 只有 contents：把目录之前全部当作简介。
      selected = paragraphs.sublist(0, contentsIdx);
    } else {
      // 只命中 intro 缺右边界容易把整篇正文吞进去；保守地不抽。
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
