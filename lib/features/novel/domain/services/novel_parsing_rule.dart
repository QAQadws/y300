import 'package:y300/features/novel/domain/models/novel_parsing_models.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

abstract class NovelParsingRule {
  const NovelParsingRule();

  NovelRuleResult apply(NovelParsingContext context);
}

class NovelParsingContext {
  const NovelParsingContext({
    required this.novelId,
    required this.page,
    required this.post,
    required this.opAuthorId,
    required this.domExtractor,
    required this.currentOrderIndex,
    required this.plainText,
    required this.paragraphs,
    required this.imageUrls,
    required this.headingTexts,
  });

  final String novelId;
  final ThreadDetailData page;
  final ThreadPost post;
  final String opAuthorId;
  final ForumPostDomExtractor domExtractor;
  final int currentOrderIndex;
  final String plainText;
  final List<String> paragraphs;
  final List<String> imageUrls;
  final List<String> headingTexts;
}

class NovelRuleResult {
  const NovelRuleResult({
    this.rejectPost = false,
    this.acceptAsEpisode = false,
    this.titleCandidate,
    this.paragraphs,
    this.imageUrls = const <String>[],
    this.intro,
    this.coverImageUrl,
    this.usedFallbackTitle = false,
    this.signals = const <NovelParsingSignal>[],
  });

  static const NovelRuleResult empty = NovelRuleResult();

  final bool rejectPost;
  final bool acceptAsEpisode;
  final String? titleCandidate;
  final List<String>? paragraphs;
  final List<String> imageUrls;
  final String? intro;
  final String? coverImageUrl;
  final bool usedFallbackTitle;
  final List<NovelParsingSignal> signals;

  NovelRuleResult merge(NovelRuleResult other) {
    final hasExistingTitle = titleCandidate?.trim().isNotEmpty ?? false;
    return NovelRuleResult(
      rejectPost: rejectPost || other.rejectPost,
      acceptAsEpisode: acceptAsEpisode || other.acceptAsEpisode,
      titleCandidate: _firstNonBlank(titleCandidate, other.titleCandidate),
      paragraphs: paragraphs ?? other.paragraphs,
      imageUrls: imageUrls.isEmpty ? other.imageUrls : imageUrls,
      intro: _firstNonBlank(intro, other.intro),
      coverImageUrl: _firstNonBlank(coverImageUrl, other.coverImageUrl),
      usedFallbackTitle:
          usedFallbackTitle || (!hasExistingTitle && other.usedFallbackTitle),
      signals: <NovelParsingSignal>[...signals, ...other.signals],
    );
  }

  String? _firstNonBlank(String? first, String? second) {
    final normalizedFirst = first?.trim();
    if (normalizedFirst != null && normalizedFirst.isNotEmpty) {
      return normalizedFirst;
    }
    final normalizedSecond = second?.trim();
    return normalizedSecond == null || normalizedSecond.isEmpty
        ? null
        : normalizedSecond;
  }
}

class NovelParsingRules {
  const NovelParsingRules._();

  static const List<NovelParsingRule> defaults = <NovelParsingRule>[
    OpAuthorOnlyRule(),
    MeaningfulTextRule(),
    HeadingTitleRule(),
    ChapterTitleRegexRule(),
    CoverImageRule(),
    IntroBeforeFirstChapterRule(),
    FallbackTitleRule(),
  ];
}

class OpAuthorOnlyRule extends NovelParsingRule {
  const OpAuthorOnlyRule();

  @override
  NovelRuleResult apply(NovelParsingContext context) {
    if (context.opAuthorId.isEmpty ||
        context.post.authorId == context.opAuthorId) {
      return NovelRuleResult.empty;
    }
    return NovelRuleResult(
      rejectPost: true,
      signals: <NovelParsingSignal>[
        NovelParsingSignal(
          stage: 'author',
          message: 'skip non-op pid=${context.post.pid}',
        ),
      ],
    );
  }
}

class MeaningfulTextRule extends NovelParsingRule {
  const MeaningfulTextRule({this.minTextLength = 1});

  final int minTextLength;

  @override
  NovelRuleResult apply(NovelParsingContext context) {
    final hasText = context.plainText.trim().length >= minTextLength;
    final hasImages = context.imageUrls.isNotEmpty;
    if (!hasText && !hasImages) {
      return NovelRuleResult(
        rejectPost: true,
        signals: <NovelParsingSignal>[
          NovelParsingSignal(
            stage: 'content',
            message: 'skip empty pid=${context.post.pid}',
          ),
        ],
      );
    }
    return NovelRuleResult(
      acceptAsEpisode: true,
      paragraphs: context.paragraphs,
      imageUrls: context.imageUrls,
    );
  }
}

class ChapterTitleRegexRule extends NovelParsingRule {
  const ChapterTitleRegexRule();

  static final RegExp _titlePattern = RegExp(
    r'(第\s*[0-9一二三四五六七八九十百千零〇两\.]+\s*[章节话回卷]|卷\s*[0-9一二三四五六七八九十百千零〇两\.]+|番外|特典)',
  );
  static final RegExp _asciiChapterPattern = RegExp(r'(第\s*\d+\s*[章节话回卷])');
  static final RegExp _numberedTitleLinePattern = RegExp(
    r'(^|\n)\s*(\d{1,4}\s+[^\n]{1,80})',
  );

  @override
  NovelRuleResult apply(NovelParsingContext context) {
    final title = extractTitle(context.plainText);
    if (title == null) {
      return NovelRuleResult.empty;
    }
    return NovelRuleResult(
      titleCandidate: title,
      signals: <NovelParsingSignal>[
        NovelParsingSignal(
          stage: 'title',
          message: 'regex title="$title" pid=${context.post.pid}',
        ),
      ],
    );
  }

  static String? extractTitle(String text) {
    final titleMatch =
        _titlePattern.firstMatch(text) ?? _asciiChapterPattern.firstMatch(text);
    final title = titleMatch?.group(1)?.replaceAll(RegExp(r'\s+'), '');
    if (title != null && title.isNotEmpty) {
      return title;
    }
    final numbered = _numberedTitleLinePattern
        .firstMatch(text)
        ?.group(2)
        ?.trim();
    if (numbered != null && numbered.isNotEmpty) {
      return numbered;
    }
    return null;
  }

  static int? firstTitleStart(String text) {
    return (_titlePattern.firstMatch(text) ??
            _asciiChapterPattern.firstMatch(text) ??
            _numberedTitleLinePattern.firstMatch(text))
        ?.start;
  }
}

class HeadingTitleRule extends NovelParsingRule {
  const HeadingTitleRule();

  @override
  NovelRuleResult apply(NovelParsingContext context) {
    for (final heading in context.headingTexts) {
      if (heading.length > 80) {
        continue;
      }
      final title = ChapterTitleRegexRule.extractTitle(heading);
      if (title != null) {
        return NovelRuleResult(
          titleCandidate: title,
          signals: <NovelParsingSignal>[
            NovelParsingSignal(
              stage: 'title',
              message: 'heading title="$title" pid=${context.post.pid}',
            ),
          ],
        );
      }
    }
    return NovelRuleResult.empty;
  }
}

class CoverImageRule extends NovelParsingRule {
  const CoverImageRule();

  @override
  NovelRuleResult apply(NovelParsingContext context) {
    if (context.currentOrderIndex != 0 || context.imageUrls.isEmpty) {
      return NovelRuleResult.empty;
    }
    return NovelRuleResult(
      coverImageUrl: context.imageUrls.first,
      signals: <NovelParsingSignal>[
        NovelParsingSignal(
          stage: 'cover',
          message: 'cover candidate pid=${context.post.pid}',
        ),
      ],
    );
  }
}

class IntroBeforeFirstChapterRule extends NovelParsingRule {
  const IntroBeforeFirstChapterRule({this.maxIntroLength = 600});

  final int maxIntroLength;

  @override
  NovelRuleResult apply(NovelParsingContext context) {
    if (context.currentOrderIndex != 0) {
      return NovelRuleResult.empty;
    }
    final titleStart = ChapterTitleRegexRule.firstTitleStart(context.plainText);
    if (titleStart == null || titleStart <= 0) {
      return NovelRuleResult.empty;
    }
    final intro = context.plainText.substring(0, titleStart).trim();
    if (intro.isEmpty) {
      return NovelRuleResult.empty;
    }
    final clipped = intro.length > maxIntroLength
        ? intro.substring(0, maxIntroLength).trim()
        : intro;
    return NovelRuleResult(
      intro: clipped,
      signals: <NovelParsingSignal>[
        NovelParsingSignal(
          stage: 'intro',
          message: 'intro candidate pid=${context.post.pid}',
        ),
      ],
    );
  }
}

class FallbackTitleRule extends NovelParsingRule {
  const FallbackTitleRule();

  @override
  NovelRuleResult apply(NovelParsingContext context) {
    final title = context.post.number == 1 || context.currentOrderIndex == 0
        ? '序章'
        : '第${context.currentOrderIndex + 1}节（PID:${context.post.pid}）';
    return NovelRuleResult(
      titleCandidate: title,
      usedFallbackTitle: true,
      signals: <NovelParsingSignal>[
        NovelParsingSignal(
          stage: 'title',
          message: 'fallback title="$title" pid=${context.post.pid}',
        ),
      ],
    );
  }
}
