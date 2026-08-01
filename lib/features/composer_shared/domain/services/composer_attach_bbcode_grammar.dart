/// `[attach]aid[/attach]` and `[attachimg]aid[/attachimg]` grammar.
///
/// Discuz only treats a positive-integer aid wrapped by one of the two
/// attachment tags as an inline attachment.
/// 上传接口回传的 aid 也一定是正整数（见 `DiscuzComposerAttachmentRepository`），
/// Every editor structure decision (Quill decoding, literal-token promotion
/// and logical-offset mapping) must use this grammar instead of duplicating
/// regular expressions.
///
/// [ComposerAttachBbCodeService] remains intentionally more tolerant for
/// extracting and cleaning old drafts and server-returned text.
enum ComposerAttachTagKind {
  attach('attach'),
  attachImg('attachimg');

  const ComposerAttachTagKind(this.wireName);

  final String wireName;
}

class ComposerAttachBbCodeGrammar {
  const ComposerAttachBbCodeGrammar();

  /// Does not contain capture groups so it can be composed into larger regexes.
  static const String tokenPatternSource =
      r'(?:\[attach\][1-9]\d*\[/attach\]|'
      r'\[attachimg\][1-9]\d*\[/attachimg\])';

  static final RegExp _tokenPattern = RegExp(
    tokenPatternSource,
    caseSensitive: false,
  );
  static final RegExp _exactTokenPattern = RegExp(
    '^$tokenPatternSource\$',
    caseSensitive: false,
  );
  static final RegExp _aidPattern = RegExp(r'^[1-9]\d*$');

  /// Whether the whole string is one legal attachment code.
  bool isLegalCode(String token) => _exactTokenPattern.hasMatch(token);

  bool isLegalAid(String aid) => _aidPattern.hasMatch(aid);

  String codeFor(
    String aid, [
    ComposerAttachTagKind kind = ComposerAttachTagKind.attach,
  ]) {
    return '[${kind.wireName}]${aid.trim()}[/${kind.wireName}]';
  }

  /// Returns the aid from a legal code, otherwise null.
  String? aidOf(String token) {
    if (!isLegalCode(token)) {
      return null;
    }
    return scan(token).single.aid;
  }

  /// Scans legal attachment codes in source order.
  List<ComposerAttachToken> scan(String source) {
    if (source.isEmpty) {
      return const <ComposerAttachToken>[];
    }
    return [
      for (final match in _tokenPattern.allMatches(source))
        _tokenFromMatch(match.group(0)!, match.start, match.end),
    ];
  }

  ComposerAttachToken _tokenFromMatch(String rawCode, int start, int end) {
    final lower = rawCode.toLowerCase();
    final kind = lower.startsWith('[attachimg]')
        ? ComposerAttachTagKind.attachImg
        : ComposerAttachTagKind.attach;
    final openingLength = kind == ComposerAttachTagKind.attachImg
        ? '[attachimg]'.length
        : '[attach]'.length;
    final closingLength = kind == ComposerAttachTagKind.attachImg
        ? '[/attachimg]'.length
        : '[/attach]'.length;
    return ComposerAttachToken(
      aid: rawCode.substring(openingLength, rawCode.length - closingLength),
      kind: kind,
      start: start,
      end: end,
      rawCode: rawCode,
    );
  }
}

final class ComposerAttachToken {
  const ComposerAttachToken({
    required this.aid,
    required this.kind,
    required this.start,
    required this.end,
    required this.rawCode,
  });

  final String aid;
  final ComposerAttachTagKind kind;
  final int start;
  final int end;
  final String rawCode;

  int get length => end - start;
}

/// Source compatibility for Phase 1 callers and existing tests.
typedef ComposerAttachTokenMatch = ComposerAttachToken;
