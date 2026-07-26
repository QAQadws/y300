/// `[attach]aid[/attach]` 的规范文法：判定"这串字符是不是合法的附件代码"。
///
/// Discuz 只把 `[attach]` + 纯数字 aid + `[/attach]` 解析成内联附件，
/// 上传接口回传的 aid 也一定是正整数（见 `DiscuzComposerAttachmentRepository`），
/// 所以合法性只有这一个口径。编辑器里凡是要做"结构判定"的地方
/// （Quill 解码、字面 token 归一、逻辑偏移映射）都从这里取模式，
/// 避免各写一份正则之后彼此漂移。
///
/// 注意与 [ComposerAttachBbCodeService] 的分工：本文法管编辑器结构，
/// 那边的宽松匹配管提取与清理（要兜住历史草稿和服务端脏数据）。
class ComposerAttachBbCodeGrammar {
  const ComposerAttachBbCodeGrammar();

  /// 不含捕获组，便于拼进更大的复合 token 正则。
  static const String tokenPatternSource = r'\[attach\]\d+\[/attach\]';

  static final RegExp _tokenPattern = RegExp(
    r'\[attach\](\d+)\[/attach\]',
    caseSensitive: false,
  );
  static final RegExp _exactTokenPattern = RegExp(
    '^$tokenPatternSource\$',
    caseSensitive: false,
  );
  static final RegExp _aidPattern = RegExp(r'^\d+$');

  /// 整串是否恰好是一个合法附件代码。
  bool isLegalCode(String token) => _exactTokenPattern.hasMatch(token);

  bool isLegalAid(String aid) => _aidPattern.hasMatch(aid);

  String codeFor(String aid) => '[attach]${aid.trim()}[/attach]';

  /// 合法代码返回其中的 aid，否则返回 null。
  String? aidOf(String token) {
    if (!isLegalCode(token)) {
      return null;
    }
    return _tokenPattern.firstMatch(token)?.group(1);
  }

  /// 按出现顺序扫描出所有合法附件代码及其位置。
  List<ComposerAttachTokenMatch> scan(String source) {
    if (source.isEmpty) {
      return const <ComposerAttachTokenMatch>[];
    }
    return [
      for (final match in _tokenPattern.allMatches(source))
        ComposerAttachTokenMatch(
          aid: match.group(1)!,
          start: match.start,
          end: match.end,
        ),
    ];
  }
}

class ComposerAttachTokenMatch {
  const ComposerAttachTokenMatch({
    required this.aid,
    required this.start,
    required this.end,
  });

  final String aid;
  final int start;
  final int end;

  int get length => end - start;
}
