import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_analyzer.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_grammar.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_rules.dart';

/// Parses forum thread subject lines into structured comic metadata.
///
/// Design goals:
/// 1. Keep heuristics out of repository and UI.
/// 2. Be easy to extend with new normalization rules.
/// 3. Produce best-effort metadata without breaking existing behavior.
abstract class ComicSubjectParser {
  ComicSubjectMetadata parse(String subject);
}

/// 收藏/详情/阅读链路对外的稳定入口。阶段 1 把核心解析下沉到
/// [ComicTitleAnalyzer]（默认 [PetitComicTitleAnalyzer]），本类负责把
/// analyzer 输出映射到老的 [ComicSubjectMetadata] 字段，方便逐步迁移调用方。
class RuleBasedComicSubjectParser implements ComicSubjectParser {
  const RuleBasedComicSubjectParser({
    ComicTitleAnalyzer analyzer = const PetitComicTitleAnalyzer(),
  }) : _analyzer = analyzer;

  final ComicTitleAnalyzer _analyzer;
  static const ComicTitleGrammar _grammar = ComicTitleGrammar();

  @override
  ComicSubjectMetadata parse(String subject) {
    final raw = subject.trim();
    if (raw.isEmpty) {
      return const ComicSubjectMetadata(normalizedTitle: '');
    }

    final analysis = _analyzer.analyze(raw);
    final leadingMetadata = _grammar.parseLeadingMetadata(raw);
    final bracketTokens = leadingMetadata.tokens
        .map((token) => token.value)
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final translationGroup = _pickTranslationGroup(bracketTokens);
    final inferredAuthor = _nonEmptyOrNull(analysis.authorPrefix) ??
        ComicTitleRules.extractAuthorHint(raw) ??
        _pickAuthorFromTokens(bracketTokens);
    final normalizedTitle = _nonEmptyOrNull(analysis.cleanBookName) ?? raw;
    final episodeLabel = _nonEmptyOrNull(analysis.episodeLabel);

    return ComicSubjectMetadata(
      normalizedTitle: normalizedTitle,
      translationGroup: translationGroup,
      inferredAuthor: inferredAuthor,
      episodeLabel: episodeLabel,
    );
  }

  String? _pickTranslationGroup(List<String> tokens) {
    for (final token in tokens) {
      if (ComicTitleRules.looksLikeTranslationGroup(token)) {
        return token;
      }
    }
    return null;
  }

  String? _pickAuthorFromTokens(List<String> tokens) {
    for (final token in tokens.reversed) {
      if (!ComicTitleRules.looksLikeTranslationGroup(token) &&
          !ComicTitleRules.isComiketToken(token) &&
          token.length <= 24) {
        return token;
      }
    }
    return null;
  }

  String? _nonEmptyOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
