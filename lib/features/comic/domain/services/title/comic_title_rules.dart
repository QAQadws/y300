final class ComicTitleRules {
  const ComicTitleRules._();

  // 仅 `【...】` 和 `[...]` 才是漫画标题里的前缀 bracket（汉化组 / 作者）。
  // `《...》、(...)、（...）、〔...〕、「...」、『...』` 在真实样本中是书名/译名的一部分，
  // 当作前缀解析会把书名吃掉，例如 `《我爱艾米》(나는에이미를사랑해) 第46话`。
  static const String leadingBracketOpenCharacters = '[【';
  static const String leadingBracketCloseCharacters = ']】';

  // 标题正文截断符。仅 `|｜` 在真实样本中作为强分隔（论坛尾巴/版块标签前缀），
  // 其余如 `~`、`-` 在真实漫画标题里大量作装饰用，因此不放进截断列表，避免误伤。
  static const List<String> separatorTokens = <String>['|', '｜'];

  // 翻译/汉化组识别提示。仅保留真实可读字符；阶段 1 早期版本曾把
  // GBK 解码为 UTF-8 产生的 mojibake 也写进列表，但那是源 Kotlin 文件被错误
  // 解码后产生的噪声，对 UTF-8 正常文本不会触发。
  static const List<String> translationGroupHints = <String>[
    '汉化组',
    '漢化組',
    '漫化组',
    '漫化組',
    '翻译组',
    '翻譯組',
    '汉化',
    '漢化',
    '漫化',
    '翻译',
    '翻譯',
    'scan',
    '组',
    '組',
  ];

  static const List<String> specialEpisodeMarkers = <String>[
    '卷后附录',
    '卷後附錄',
    '卷附录',
    '卷附錄',
    '卷彩页',
    '卷彩頁',
    '小剧场',
    '小劇場',
    '小漫画',
    '小漫畫',
    '单行本',
    '單行本',
    '番外',
    '特典',
    '附录',
    '附錄',
    '短篇',
    'SP',
  ];

  static const List<String> finalEpisodeMarkers = <String>[
    '最终话',
    '最終話',
    '最终回',
    '最終回',
    '大结局',
    '大結局',
  ];

  static const Map<String, String> asciiPunctuationNormalization =
      <String, String>{'．': '.', '：': ':', '＃': '#', '～': '~', '　': ' '};

  static const String numberTokenCharacters =
      r'0-9０-９零〇一二两兩三四五六七八九十百千ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩⅪⅫIVXLCDMivxlcdm①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳';

  static String normalizeAsciiVariants(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0xFF10 && rune <= 0xFF19) {
        buffer.writeCharCode(rune - 0xFEE0);
        continue;
      }
      if (rune >= 0xFF21 && rune <= 0xFF3A) {
        buffer.writeCharCode(rune - 0xFEE0);
        continue;
      }
      if (rune >= 0xFF41 && rune <= 0xFF5A) {
        buffer.writeCharCode(rune - 0xFEE0);
        continue;
      }
      final char = String.fromCharCode(rune);
      buffer.write(asciiPunctuationNormalization[char] ?? char);
    }
    return buffer.toString();
  }

  static String normalizeWhitespace(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String normalizeHtmlEntities(String input) {
    // 论坛标题里偶尔会残留 HTML 实体，先解码常见实体避免污染书名匹配。
    var decoded = input;
    while (decoded.contains('&amp;')) {
      decoded = decoded.replaceAll('&amp;', '&');
    }
    return decoded;
  }

  static String normalizeForMatching(String input) {
    return normalizeWhitespace(
      normalizeAsciiVariants(normalizeHtmlEntities(input)),
    );
  }

  static String trimOuterSeparators(String input) {
    // 不剥离 `~`：副标题装饰常出现在书名内部和外缘（例如 `~机动战士~`），
    // 阶段 1 仅去掉空白、连字符、下划线、斜杠和冒号。
    var value = input.trim();
    value = value.replaceAll(RegExp(r'^[\s_\-|:：/]+'), '');
    value = value.replaceAll(RegExp(r'[\s_\-|:：/]+$'), '');
    value = value.replaceAll(RegExp(r'[!！?？,，.。．、…]+$'), '');
    value = value.replaceAll(RegExp(r'[\[(（【『「]+$'), '');
    return value.trim();
  }

  static bool looksLikeTranslationGroup(String token) {
    final normalized = normalizeForMatching(token).toLowerCase();
    return translationGroupHints.any(
      (hint) => normalized.contains(normalizeForMatching(hint).toLowerCase()),
    );
  }

  static bool isComiketToken(String token) {
    final normalized = normalizeForMatching(token);
    return RegExp(
      r'^(?:C|COMIKET)\s*\d{2,4}$',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  static String? extractAuthorHint(String raw) {
    final normalized = normalizeForMatching(raw);
    final match = RegExp(
      r'(?:原作|作者|作画|作畫)\s*[：:]\s*([^\]】\)）/\|]+)',
      caseSensitive: false,
    ).firstMatch(normalized);
    final author = match?.group(1)?.trim();
    if (author == null || author.isEmpty) {
      return null;
    }
    return author;
  }
}
