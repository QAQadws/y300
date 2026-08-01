import 'comic_title_analysis.dart';
import 'comic_title_grammar.dart';
import 'comic_title_number_parser.dart';
import 'comic_title_rules.dart';

abstract class ComicTitleAnalyzer {
  const ComicTitleAnalyzer();

  ComicTitleAnalysis analyze(String rawTitle);

  String? extractTidFromUrl(String url);
}

class PetitComicTitleAnalyzer implements ComicTitleAnalyzer {
  const PetitComicTitleAnalyzer({
    ComicTitleGrammar grammar = const ComicTitleGrammar(),
    ComicTitleNumberParser numberParser = const ComicTitleNumberParser(),
  }) : _grammar = grammar,
       _numberParser = numberParser;

  final ComicTitleGrammar _grammar;
  final ComicTitleNumberParser _numberParser;

  // 中文章节标记字符。Kotlin 源使用 `话話织回章节幕折更`；这里保留同样的集合，
  // 顺带兼容繁体 `話`，让 `第N织` / `19话` / `5幕` 都能识别。
  static const String _chapterUnitCharacters = '话話织回章节幕折更';

  // 特殊/位置标记关键词匹配。
  // 不限制前缀边界——后处理逻辑通过回溯吸收尾部数字/卷号前缀，
  // 从而正确拆分 `致彼时繁花05 后篇`、`LOVE·BULLET 二卷番外`、
  // `ハムスター大作戦）下篇`、`口腔…前篇` 等场景。
  static final RegExp _specialMarkerPattern = RegExp(
    r'(?:卷后附录|卷後附錄|卷附录|卷附錄|卷彩页|卷彩頁|小剧场|小劇場|小漫画|小漫畫|单行本|單行本|'
    r'番外|特典|附录|附錄|短篇|\bSP\b|'
    r'前篇|后篇|上篇|下篇|中篇)'
    r'[\s\S]*',
    caseSensitive: false,
  );
  static const List<String> _positionEpisodeMarkers = <String>[
    '前篇',
    '后篇',
    '上篇',
    '下篇',
    '中篇',
  ];
  static final RegExp _finalMarkerPattern = RegExp(
    r'(最终话|最終話|最终回|最終回|大结局|大結局)',
    caseSensitive: false,
  );
  // `第` 引导的章节，章节单位可选；同样接受 `第6-1话` 这种小节号形式（取主章节）。
  // 当 unit 字符不存在时，允许捕获后续非空白文本作为标签延伸（如 `第一拳`）。
  static final RegExp _chapterLabelPattern = RegExp(
    '((第)\\s*([${ComicTitleRules.numberTokenCharacters}]+(?:\\.[0-9]+)?)'
    '(?:-[0-9]+)?'
    '\\s*(?:'
    '[$_chapterUnitCharacters]\\s*'
    '(上篇|中篇|下篇|前篇|后篇|上|中|下|前|后)?\\s*[①②③④⑤⑥⑦⑧⑨]?'
    '|([^\\s上中下前后篇①②③④⑤⑥⑦⑧⑨\\-]))'
    ')',
    caseSensitive: false,
  );
  // 没有 `第` 但带章节单位的形式，例如 `19话`、`16话`、`03话`、`28话`、`第十五织`。
  // 通过 lookbehind 排除前面紧贴 ASCII 数字/字母的情况，避免把版本号或尺寸误识别。
  static final RegExp _bareChapterLabelPattern = RegExp(
    '((?<![A-Za-z0-9])([${ComicTitleRules.numberTokenCharacters}]+(?:\\.[0-9]+)?)'
    '(?:\\s*[~～-]\\s*([${ComicTitleRules.numberTokenCharacters}]+(?:\\.[0-9]+)?))?'
    '\\s*[$_chapterUnitCharacters]\\s*'
    '(上篇|中篇|下篇|前篇|后篇|上|中|下|前|后)?\\s*[①②③④⑤⑥⑦⑧⑨]?)',
    caseSensitive: false,
  );
  static final RegExp _englishLabelPattern = RegExp(
    '((Vol|Ch|EP|#)\\.?\\s*([${ComicTitleRules.numberTokenCharacters}]+(?:\\.[0-9]+)?)'
    '\\s*(上篇|中篇|下篇|前篇|后篇|上|中|下|前|后)?\\s*[①②③④⑤⑥⑦⑧⑨]?)',
    caseSensitive: false,
  );
  static final RegExp _seasonEpisodePattern = RegExp(
    '((S\\s*([0-9]+)\\s*EP\\.?\\s*([${ComicTitleRules.numberTokenCharacters}]+(?:\\.[0-9]+)?)))',
    caseSensitive: false,
  );
  static final RegExp _trailingNumberPattern = RegExp(
    '([${ComicTitleRules.numberTokenCharacters}]+(?:\\.[0-9]+)?)\\s*\$',
    caseSensitive: false,
  );
  static final RegExp _circledDigitPattern = RegExp(r'[①②③④⑤⑥⑦⑧⑨]');
  static final RegExp _leadingComiketPattern = RegExp(
    r'^\s*(?:[\(（]?\s*(?:C|COMIKET)\s*\d{2,4}\s*[\)）]?)[\s\-_:：|]*',
    caseSensitive: false,
  );

  static final RegExp _asciiAlphaNumericPattern = RegExp(r'[A-Za-z0-9]');
  static final RegExp _romanNumberTokenPattern = RegExp(
    r'^[IVXLCDM]+$',
    caseSensitive: false,
  );

  @override
  ComicTitleAnalysis analyze(String rawTitle) {
    final raw = rawTitle.trim();
    if (raw.isEmpty) {
      return ComicTitleAnalysis.empty;
    }

    final normalized = ComicTitleRules.normalizeForMatching(raw);
    final leading = _grammar.parseLeadingMetadata(normalized);
    final authorPrefix = _pickAuthorPrefix(leading.tokens);
    final bodyWithoutComiket = _stripLeadingComiketTokens(leading.remainder);
    final bodyBeforeSeparator = _truncateAtSeparator(bodyWithoutComiket);
    final chapter = _extractChapter(bodyBeforeSeparator);
    var cleanBookName = _cleanupBookName(chapter.bookSegment);
    if (cleanBookName.isEmpty) {
      cleanBookName = _cleanupBookName(bodyBeforeSeparator);
    }
    if (cleanBookName.isEmpty) {
      cleanBookName = _cleanupBookName(normalized);
    }

    return ComicTitleAnalysis(
      rawTitle: raw,
      cleanBookName: cleanBookName,
      searchKeyword: _clipSearchKeyword(cleanBookName),
      authorPrefix: authorPrefix,
      episodeLabel: chapter.episodeLabel,
      chapterNumber: chapter.chapterNumber,
      possibleChapterNumbers: chapter.possibleChapterNumbers,
    );
  }

  @override
  String? extractTidFromUrl(String url) {
    final raw = url.trim();
    if (raw.isEmpty) {
      return null;
    }

    final queryMatch = RegExp(
      r'(^|[?&;])tid=(\d+)(?:[&#]|$)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (queryMatch != null) {
      return queryMatch.group(2);
    }

    final threadMatch = RegExp(
      r'thread-(\d+)-',
      caseSensitive: false,
    ).firstMatch(raw);
    return threadMatch?.group(1);
  }

  String? _pickAuthorPrefix(List<ComicLeadingBracketToken> tokens) {
    for (final token in tokens.reversed) {
      final value = ComicTitleRules.normalizeForMatching(token.value);
      if (value.isEmpty ||
          ComicTitleRules.looksLikeTranslationGroup(value) ||
          ComicTitleRules.isComiketToken(value)) {
        continue;
      }
      return value;
    }
    return null;
  }

  String _stripLeadingComiketTokens(String input) {
    var remainder = input;
    while (true) {
      final match = _leadingComiketPattern.firstMatch(remainder);
      if (match == null) {
        break;
      }
      remainder = remainder.substring(match.end);
    }
    return remainder.trimLeft();
  }

  String _truncateAtSeparator(String input) {
    var boundary = input.length;
    for (final separator in ComicTitleRules.separatorTokens) {
      final index = input.indexOf(separator);
      if (index >= 0 && index < boundary) {
        boundary = index;
      }
    }
    return input.substring(0, boundary).trimRight();
  }

  String _cleanupBookName(String input) {
    var value = ComicTitleRules.trimOuterSeparators(input);
    value = value.replaceAll(RegExp(r'[\s_\-:：]+\d+$'), '');
    value = value.replaceAll(RegExp(r'[\s_\-:：]+$'), '');
    value = value.replaceAll(RegExp(r'[!！?？,，.。．、…]+$'), '');
    return value.trim();
  }

  String _clipSearchKeyword(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final runes = trimmed.runes.toList(growable: false);
    if (runes.length <= 18) {
      return trimmed;
    }
    return String.fromCharCodes(runes.take(18));
  }

  _ChapterExtraction _extractChapter(String input) {
    final possibleNumbers = <double>[];
    final finalMatch = _finalMarkerPattern.firstMatch(input);
    if (finalMatch != null) {
      _addPossibleNumber(possibleNumbers, 999);
      return _ChapterExtraction(
        bookSegment: input.substring(0, finalMatch.start),
        episodeLabel: '最终话',
        chapterNumber: 999,
        possibleChapterNumbers: possibleNumbers,
      );
    }

    final specialMatch = _specialMarkerPattern.firstMatch(input);
    if (specialMatch != null) {
      final matchStart = _specialEpisodeStart(input, specialMatch);

      if (matchStart != null) {
        // episodeLabel 保留原始文本，不规范化。
        final fullLabel = input.substring(matchStart).trim();

        // 仅当 episodeLabel 内含最终话标记时覆盖为 '最终话'。
        if (_finalMarkerPattern.hasMatch(fullLabel)) {
          _addPossibleNumber(possibleNumbers, 999);
          return _ChapterExtraction(
            bookSegment: input.substring(0, matchStart),
            episodeLabel: '最终话',
            chapterNumber: 999,
            possibleChapterNumbers: possibleNumbers,
          );
        }

        // chapterNumber 推导：
        // 1. 尝试解析 episodeLabel 前导 ASCII 数字（如 `05 后篇` → 5）。
        // 2. 从标记关键词前的前缀文本中提取中文数字（如 `二卷番外` → 2）。
        double chapterNumber = 0;
        final leadingDigits = RegExp(r'^(\d+)').firstMatch(fullLabel);
        if (leadingDigits != null) {
          chapterNumber = double.tryParse(leadingDigits.group(1)!) ?? 0;
        } else {
          // 找到最长匹配的特殊标记关键词，提取其前面的文本作为中文数字源。
          String? longestKeyword;
          for (final marker in ComicTitleRules.specialEpisodeMarkers) {
            if (fullLabel.contains(marker) &&
                (longestKeyword == null ||
                    marker.length > longestKeyword.length)) {
              longestKeyword = marker;
            }
          }
          if (longestKeyword != null) {
            final keywordIndex = fullLabel.indexOf(longestKeyword);
            if (keywordIndex > 0) {
              final prefixText = fullLabel.substring(0, keywordIndex);
              final chineseNumber = _extractLeadingChineseNumber(prefixText);
              if (chineseNumber != null) {
                chapterNumber = chineseNumber.toDouble();
              }
            }
          }
        }
        _addPossibleNumber(possibleNumbers, chapterNumber);

        return _ChapterExtraction(
          bookSegment: input.substring(0, matchStart),
          episodeLabel: fullLabel,
          chapterNumber: chapterNumber,
          possibleChapterNumbers: possibleNumbers,
        );
      }
    }

    final chapterMatch = _chapterLabelPattern.firstMatch(input);
    if (chapterMatch != null) {
      // 检查匹配文本自身的末尾字符是否为章节 unit 字符或修饰符。
      // 使用 group(1) 而非 group(0)，因为 group(0) 末尾的 \s* 会贪吃空格。
      final matchedLabel = chapterMatch.group(1)?.trim() ?? '';
      final lastChar = matchedLabel.isNotEmpty
          ? matchedLabel[matchedLabel.length - 1]
          : '';
      final extension = chapterMatch.group(5);
      final hasUnitOrModifier =
          _chapterUnitCharacters.contains(lastChar) ||
          '上中下前后篇①②③④⑤⑥⑦⑧⑨'.contains(lastChar) ||
          RegExp(r'[0-9０-９]').hasMatch(lastChar) ||
          (extension != null && extension.isNotEmpty);
      if (hasUnitOrModifier) {
        final label = chapterMatch.group(1)?.trim() ?? '';
        final base = _numberParser.parseNumber(chapterMatch.group(3) ?? '');
        final part = chapterMatch.group(4);

        double? chapterNumber;
        String episodeLabel;

        if (extension != null && extension.isNotEmpty) {
          // 延伸分支：episodeLabel 保留原文（如 `第一拳`）。
          episodeLabel = matchedLabel;
          chapterNumber = base;
        } else {
          // 标准分支：保持现有规范化行为（如 `第2话上`）。
          final adjusted = _applyChapterModifier(base, label, part);
          chapterNumber = adjusted;
          episodeLabel = _canonicalizeChapterLabel(base, part, label);
        }

        if (chapterNumber != null) {
          _addPossibleNumber(possibleNumbers, chapterNumber);
        }
        if (base != null && chapterNumber != base) {
          _addPossibleNumber(possibleNumbers, base);
        }
        return _ChapterExtraction(
          bookSegment: input.substring(0, chapterMatch.start),
          episodeLabel: episodeLabel,
          chapterNumber: chapterNumber,
          possibleChapterNumbers: possibleNumbers,
        );
      }
    }

    final englishMatch = _firstStandaloneEnglishLabelMatch(input);
    if (englishMatch != null) {
      final marker = (englishMatch.group(2) ?? '').trim();
      final base = _numberParser.parseNumber(englishMatch.group(3) ?? '');
      final part = englishMatch.group(4);
      final adjusted = _applyChapterModifier(
        base,
        englishMatch.group(1) ?? '',
        part,
      );
      if (adjusted != null) {
        _addPossibleNumber(possibleNumbers, adjusted);
      }
      if (base != null && adjusted != base) {
        _addPossibleNumber(possibleNumbers, base);
      }
      return _ChapterExtraction(
        bookSegment: input.substring(0, englishMatch.start),
        episodeLabel: _canonicalizeEnglishLabel(marker, base, part),
        chapterNumber: adjusted,
        possibleChapterNumbers: possibleNumbers,
      );
    }

    final bareChapterMatch = _bareChapterLabelPattern.firstMatch(input);
    if (bareChapterMatch != null) {
      final label = bareChapterMatch.group(1)?.trim() ?? '';
      final base = _numberParser.parseNumber(bareChapterMatch.group(2) ?? '');
      final rangeEnd = bareChapterMatch.group(3);
      final part = bareChapterMatch.group(4);
      final adjusted = _applyChapterModifier(base, label, part);
      if (adjusted != null) {
        _addPossibleNumber(possibleNumbers, adjusted);
      }
      final endNumber = _numberParser.parseNumber(rangeEnd ?? '');
      if (endNumber != null) {
        _addPossibleNumber(possibleNumbers, endNumber);
      }
      if (base != null && adjusted != base) {
        _addPossibleNumber(possibleNumbers, base);
      }
      return _ChapterExtraction(
        bookSegment: input.substring(0, bareChapterMatch.start),
        episodeLabel: rangeEnd == null
            ? _canonicalizeChapterLabel(base, part, label)
            : label,
        chapterNumber: adjusted,
        possibleChapterNumbers: possibleNumbers,
      );
    }

    final seasonMatch = _seasonEpisodePattern.firstMatch(input);
    if (seasonMatch != null) {
      final episodeNumber = _numberParser.parseNumber(
        seasonMatch.group(4) ?? '',
      );
      if (episodeNumber != null) {
        _addPossibleNumber(possibleNumbers, episodeNumber);
      }
      final season = seasonMatch.group(3)?.trim() ?? '';
      return _ChapterExtraction(
        bookSegment: input.substring(0, seasonMatch.start),
        episodeLabel: season.isEmpty
            ? 'EP${_formatNumber(episodeNumber)}'
            : 'S$season EP${_formatNumber(episodeNumber)}',
        chapterNumber: episodeNumber,
        possibleChapterNumbers: possibleNumbers,
      );
    }

    final trailingMatch = _standaloneTrailingNumberMatch(input);
    if (trailingMatch != null) {
      final base = _numberParser.parseNumber(trailingMatch.group(1) ?? '');
      if (base != null) {
        _addPossibleNumber(possibleNumbers, base);
        return _ChapterExtraction(
          bookSegment: input.substring(0, trailingMatch.start),
          episodeLabel: _formatNumber(base),
          chapterNumber: base,
          possibleChapterNumbers: possibleNumbers,
        );
      }
    }

    return _ChapterExtraction(
      bookSegment: input,
      possibleChapterNumbers: possibleNumbers,
    );
  }

  RegExpMatch? _firstStandaloneEnglishLabelMatch(String input) {
    for (final match in _englishLabelPattern.allMatches(input)) {
      if (_isStandaloneEnglishLabelMatch(input, match)) {
        return match;
      }
    }
    return null;
  }

  int? _specialEpisodeStart(String input, RegExpMatch specialMatch) {
    final markerStart = specialMatch.start;
    final isPositionMarker = _positionEpisodeMarkers.any(
      (marker) => input.startsWith(marker, markerStart),
    );
    if (isPositionMarker) {
      return _positionEpisodeStart(input, markerStart);
    }

    if (markerStart == 0) {
      return markerStart;
    }

    final previous = input[markerStart - 1];
    if (_isWhitespace(previous)) {
      return markerStart;
    }

    final tokenStart = _startOfCurrentToken(input, markerStart);
    final prefix = input.substring(tokenStart, markerStart).trim();
    if (_looksLikeSpecialEpisodePrefix(prefix)) {
      return tokenStart;
    }

    return null;
  }

  int _positionEpisodeStart(String input, int markerStart) {
    if (markerStart == 0) {
      return markerStart;
    }

    var cursor = markerStart - 1;
    if (!_isWhitespace(input[cursor])) {
      return markerStart;
    }

    while (cursor >= 0 && _isWhitespace(input[cursor])) {
      cursor--;
    }
    if (cursor < 0) {
      return markerStart;
    }

    final tokenEnd = cursor + 1;
    final beforeMarker = input.substring(0, tokenEnd);
    final numberMatch = _lastEpisodeNumberMatch(beforeMarker);
    return numberMatch == null ? markerStart : numberMatch.start;
  }

  int _startOfCurrentToken(String input, int endExclusive) {
    var cursor = endExclusive - 1;
    while (cursor >= 0 && !_isWhitespace(input[cursor])) {
      cursor--;
    }
    return cursor + 1;
  }

  bool _looksLikeSpecialEpisodePrefix(String prefix) {
    if (prefix.isEmpty) {
      return false;
    }
    if (prefix.startsWith('完结') || prefix.startsWith('完結')) {
      return true;
    }
    return _extractLeadingEpisodeNumber(prefix) != null;
  }

  double? _extractLeadingEpisodeNumber(String text) {
    final match = RegExp(
      '^第?([${ComicTitleRules.numberTokenCharacters}]+(?:\\.[0-9]+)?)',
      caseSensitive: false,
    ).firstMatch(text.trimLeft());
    if (match == null) {
      return null;
    }
    return _numberParser.parseNumber(match.group(1) ?? '');
  }

  RegExpMatch? _lastEpisodeNumberMatch(String text) {
    final matches = RegExp(
      '[${ComicTitleRules.numberTokenCharacters}]+(?:\\.[0-9]+)?',
      caseSensitive: false,
    ).allMatches(text);
    RegExpMatch? result;
    for (final match in matches) {
      if (_numberParser.parseNumber(match.group(0) ?? '') != null) {
        result = match;
      }
    }
    return result;
  }

  bool _isWhitespace(String char) => RegExp(r'\s').hasMatch(char);

  bool _isStandaloneEnglishLabelMatch(String input, RegExpMatch match) {
    if (match.start > 0) {
      final previous = input.substring(match.start - 1, match.start);
      if (_asciiAlphaNumericPattern.hasMatch(previous)) {
        return false;
      }
    }

    final marker = (match.group(2) ?? '').trim().toUpperCase();
    if (marker == '#') {
      return true;
    }

    final numberToken = (match.group(3) ?? '').trim();
    if (numberToken.isEmpty) {
      return false;
    }
    if (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(numberToken)) {
      return true;
    }
    if (_romanNumberTokenPattern.hasMatch(numberToken)) {
      return true;
    }

    return !_asciiAlphaNumericPattern.hasMatch(numberToken.substring(0, 1));
  }

  RegExpMatch? _standaloneTrailingNumberMatch(String input) {
    final match = _trailingNumberPattern.firstMatch(input);
    if (match == null) {
      return null;
    }
    if (match.start > 0) {
      final previous = input.substring(match.start - 1, match.start);
      if (_asciiAlphaNumericPattern.hasMatch(previous)) {
        return null;
      }
    }
    return match;
  }

  double? _applyChapterModifier(
    double? baseNumber,
    String label,
    String? part,
  ) {
    if (baseNumber == null) {
      return null;
    }

    final circledDigit = _extractCircledDecimal(label);
    if (circledDigit != null) {
      return _normalizeChapterNumber(baseNumber + circledDigit / 10);
    }

    final normalizedPart = (part ?? '').trim();
    final decimal = switch (normalizedPart) {
      '前' || '上' || '前篇' || '上篇' => 0.1,
      '中' || '中篇' => 0.2,
      '后' || '下' || '后篇' || '下篇' => 0.3,
      _ => 0.0,
    };
    return _normalizeChapterNumber(baseNumber + decimal);
  }

  int? _extractCircledDecimal(String input) {
    final match = _circledDigitPattern.firstMatch(input);
    if (match == null) {
      return null;
    }
    return const ComicTitleNumberParser()
        .parseNumber(match.group(0) ?? '')
        ?.toInt();
  }

  /// 从文本开头提取中文数字（如 `二卷` → 2，`三` → 3）。
  /// 用于从特殊标记文本中推导 chapterNumber。
  int? _extractLeadingChineseNumber(String text) {
    const chineseNumberChars = '零〇一二两兩三四五六七八九十百千';
    final normalized = text.startsWith('第') ? text.substring(1) : text;
    var i = 0;
    while (i < normalized.length &&
        chineseNumberChars.contains(normalized[i])) {
      i++;
    }
    if (i == 0) return null;
    return _numberParser.parseNumber(normalized.substring(0, i))?.toInt();
  }

  String _canonicalizeChapterLabel(
    double? baseNumber,
    String? part,
    String rawLabel,
  ) {
    final normalizedPart = (part ?? '').trim();
    final circled = _extractCircledDecimal(rawLabel);
    final suffix = circled != null
        ? _circledCharacter(circled)
        : switch (normalizedPart) {
            '前篇' || '前' => '前',
            '上篇' || '上' => '上',
            '中篇' || '中' => '中',
            '下篇' || '下' => '下',
            '后篇' || '后' => '后',
            _ => '',
          };
    return '第${_formatNumber(baseNumber)}话$suffix';
  }

  String _canonicalizeEnglishLabel(
    String marker,
    double? baseNumber,
    String? part,
  ) {
    final normalizedMarker = marker.toUpperCase();
    final suffix = switch ((part ?? '').trim()) {
      '前篇' || '前' => '前',
      '上篇' || '上' => '上',
      '中篇' || '中' => '中',
      '下篇' || '下' => '下',
      '后篇' || '后' => '后',
      _ => '',
    };
    return switch (normalizedMarker) {
      'VOL' => 'Vol.${_formatNumber(baseNumber)}$suffix',
      'CH' => 'Ch.${_formatNumber(baseNumber)}$suffix',
      'EP' => 'EP${_formatNumber(baseNumber)}$suffix',
      '#' => '#${_formatNumber(baseNumber)}$suffix',
      _ => '$normalizedMarker${_formatNumber(baseNumber)}$suffix',
    };
  }

  String _circledCharacter(int digit) {
    const chars = <int, String>{
      1: '①',
      2: '②',
      3: '③',
      4: '④',
      5: '⑤',
      6: '⑥',
      7: '⑦',
      8: '⑧',
      9: '⑨',
    };
    return chars[digit] ?? '';
  }

  String _formatNumber(double? value) {
    if (value == null) {
      return '';
    }
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  double _normalizeChapterNumber(double input) {
    return double.parse(input.toStringAsFixed(3));
  }

  void _addPossibleNumber(List<double> values, double value) {
    final normalized = _normalizeChapterNumber(value);
    if (values.contains(normalized)) {
      return;
    }
    values.add(normalized);
  }
}

class _ChapterExtraction {
  const _ChapterExtraction({
    required this.bookSegment,
    this.episodeLabel,
    this.chapterNumber,
    this.possibleChapterNumbers = const <double>[],
  });

  final String bookSegment;
  final String? episodeLabel;
  final double? chapterNumber;
  final List<double> possibleChapterNumbers;
}
