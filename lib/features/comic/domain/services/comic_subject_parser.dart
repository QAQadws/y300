import 'package:y300/features/comic/domain/models/comic_models.dart';

/// Parses forum thread subject lines into structured comic metadata.
///
/// Design goals:
/// 1. Keep regex/heuristics out of repository and UI.
/// 2. Be easy to extend with new normalization rules.
/// 3. Produce best-effort metadata without breaking existing behavior.
abstract class ComicSubjectParser {
  ComicSubjectMetadata parse(String subject);
}

class RuleBasedComicSubjectParser implements ComicSubjectParser {
  static final RegExp _leadingBracketToken = RegExp(r'^\s*[\[【]([^\]】]+)[\]】]\s*');
  static final RegExp _episodeToken = RegExp(
    r'((第?\s*\d+(\.\d+)?\s*(话|話|卷|集|篇|章)\s*(上篇|下篇|前篇|后篇|後篇|上|中|下|前|后|後)?)|(\bEP\.?\s*\d+(\.\d+)?\b)|(\bS\d+\s*EP\d+\b)|(\s+\d+(\.\d+)?\s*$))',
    caseSensitive: false,
  );
  static final RegExp _trailingNoise = RegExp(r'[\s\-:：_]+$');
  static final RegExp _authorHint = RegExp(
    r'(原作|作画|作者)\s*[：:]\s*([^\]】\|/×xX]+)',
    caseSensitive: false,
  );

  const RuleBasedComicSubjectParser();

  @override
  ComicSubjectMetadata parse(String subject) {
    final raw = subject.trim();
    if (raw.isEmpty) {
      return const ComicSubjectMetadata(normalizedTitle: '');
    }

    final bracketTokens = <String>[];
    var cursor = raw;
    while (true) {
      final match = _leadingBracketToken.firstMatch(cursor);
      if (match == null) {
        break;
      }
      final token = match.group(1)?.trim();
      if (token != null && token.isNotEmpty) {
        bracketTokens.add(token);
      }
      cursor = cursor.substring(match.end);
    }

    final episodeMatch = _episodeToken.firstMatch(cursor);
    final episodeLabel = episodeMatch?.group(0)?.trim();
    final coreTitle = (episodeMatch == null ? cursor : cursor.substring(0, episodeMatch.start)).trim();

    final normalizedTitle = _normalizeTitle(coreTitle.isEmpty ? cursor : coreTitle);
    final translationGroup = _pickTranslationGroup(bracketTokens);
    final inferredAuthor = _pickAuthor(raw, bracketTokens);

    return ComicSubjectMetadata(
      normalizedTitle: normalizedTitle,
      translationGroup: translationGroup,
      inferredAuthor: inferredAuthor,
      episodeLabel: episodeLabel,
    );
  }

  String _normalizeTitle(String input) {
    var title = input.trim();
    title = title.replaceAll(RegExp(r'^\s*[|｜]\s*'), '');
    title = title.replaceAll(_trailingNoise, '').trim();
    return title;
  }

  String? _pickTranslationGroup(List<String> tokens) {
    for (final token in tokens) {
      if (_looksLikeTranslationGroup(token)) {
        return token;
      }
    }
    return null;
  }

  bool _looksLikeTranslationGroup(String token) {
    const hints = <String>['汉化', '漢化', '汉化组', '漢化組', '翻译', '翻譯', '组', '組'];
    return hints.any(token.contains);
  }

  String? _pickAuthor(String raw, List<String> tokens) {
    final match = _authorHint.firstMatch(raw);
    if (match != null) {
      final value = match.group(2)?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    for (final token in tokens) {
      if (!_looksLikeTranslationGroup(token) && token.length <= 24) {
        // Best-effort: first non-group bracket token is often author/circle.
        return token;
      }
    }
    return null;
  }
}
