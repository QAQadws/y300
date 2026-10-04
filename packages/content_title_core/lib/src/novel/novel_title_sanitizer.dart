/// 小说标题清洗服务。
///
/// 论坛小说的原始标题通常带有大量前导方括号 token（汉化组、长短篇标识、
/// 译者名等），这些 token 对书架/详情页的可读性是负担。把清洗逻辑收拢到
/// 单一职责的服务里，避免散落到 shelf adapter / detail header / reader
/// 等多处导致行为漂移。
abstract class NovelTitleSanitizer {
  const NovelTitleSanitizer();

  /// 返回经过实体解码并剥除前导括号 token 的标题；输入为 null/空时返回 ''。
  String sanitize(String rawTitle);
}

class DefaultNovelTitleSanitizer implements NovelTitleSanitizer {
  const DefaultNovelTitleSanitizer();

  // 行首一对 `[…]` / `【…】` / `［…］`（全角方括号），内部不允许再嵌套同类
  // 括号 —— 避免越界吞掉正文里的括号。两端可带空白，便于 `[xxx] [yyy]…`
  // 这种连写情况。全角方括号见 U+FF3B/U+FF3D，论坛小说 token 高频用。
  static final RegExp _leadingBracketPattern = RegExp(
    r'^\s*(?:\[[^\[\]]*\]|【[^【】]*】|［[^［］]*］)\s*',
  );

  @override
  String sanitize(String rawTitle) {
    var working = _decodeEntities(rawTitle).trim();
    while (working.isNotEmpty) {
      final match = _leadingBracketPattern.firstMatch(working);
      if (match == null || match.start != 0) {
        break;
      }
      working = working.substring(match.end);
    }
    return working.trim();
  }

  // 当前 spec 仅要求处理 &amp;。其它实体若日后需要可在这里集中扩展。
  String _decodeEntities(String input) {
    return input.replaceAll('&amp;', '&');
  }
}
