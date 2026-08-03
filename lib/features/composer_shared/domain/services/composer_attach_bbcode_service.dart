import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';

/// Maintains `[attach]aid[/attach]` and `[attachimg]aid[/attachimg]`
/// fragments in composer messages.
///
/// 仅依赖纯字符串处理，不感知附件状态。草稿的远端失效与显式服务器删除
/// 均保留用户 BBCode；[removeAttachCodes] 只服务明确要求改写正文的调用方。
///
/// 提取与清理同样只接受 [ComposerAttachBbCodeGrammar] 的合法 token，避免
/// 把未知/非法 aid 猜成可提交的附件引用；非法原文仍由编辑器保留。
class ComposerAttachBbCodeService {
  const ComposerAttachBbCodeService();

  static const _grammar = ComposerAttachBbCodeGrammar();

  String attachCode(String aid) {
    return attachCodeFor(aid);
  }

  String attachCodeFor(
    String aid, [
    ComposerAttachTagKind kind = ComposerAttachTagKind.attach,
  ]) {
    return _grammar.codeFor(aid, kind);
  }

  List<String> extractAttachAids(String message) {
    if (message.isEmpty) {
      return const <String>[];
    }
    return [for (final token in _grammar.scan(message)) token.aid];
  }

  String appendAttachCodes(String message, List<String> aids) {
    final normalizedAids = aids
        .map((aid) => aid.trim())
        .where((aid) => aid.isNotEmpty)
        .toList(growable: false);
    if (normalizedAids.isEmpty) {
      return message;
    }

    final attachLines = normalizedAids.map(attachCode).join('\n');
    if (message.isEmpty) {
      return attachLines;
    }
    if (message.endsWith('\n')) {
      return '$message$attachLines';
    }
    return '$message\n$attachLines';
  }

  String removeAttachCodes(String message, Iterable<String> aids) {
    final normalizedAids = aids
        .map((aid) => aid.trim())
        .where((aid) => aid.isNotEmpty)
        .toSet();
    if (message.isEmpty || normalizedAids.isEmpty) {
      return message;
    }

    final lines = message.split('\n');
    final kept = <String>[];
    for (final line in lines) {
      final aid = _exclusiveAttachAid(line);
      if (aid != null && normalizedAids.contains(aid)) {
        continue;
      }
      kept.add(line);
    }
    return kept.join('\n');
  }

  String? _exclusiveAttachAid(String line) {
    final source = line.trim();
    final tokens = _grammar.scan(source);
    if (tokens.length != 1 || tokens.single.rawCode.length != source.length) {
      return null;
    }
    return tokens.single.aid;
  }
}
