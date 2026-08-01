import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';

/// 把 Quill 文档里"字面写出来的 `[attach]aid[/attach]`"归一成 attach embed。
///
/// 用户在所见即所得模式里删掉/剪切一张图片后，再手打或粘贴回 attach 代码时，
/// 文档里只有普通文本——它不走 codec 的解码路径，因此既不会渲染成图片，
/// 也不是可整体删除的原子节点。这里负责补上这一步：合法即提升，非法保持文本，
/// 用户还能继续把 aid 改对。
///
/// 归一是 BBCode 中性的：提升前后 `encodeDocument` 的结果完全一致，
/// 所以不会额外触发 message 变更、revision 推进或草稿脏标记。
class ComposerQuillAttachTokenPromoter {
  const ComposerQuillAttachTokenPromoter({
    this.grammar = const ComposerAttachBbCodeGrammar(),
  });

  /// 逻辑文本里代表 embed 的占位符，合法 attach 代码中不可能出现，
  /// 因此扫描时不会跨越已有的图片/表情节点。
  static const String embedPlaceholder = '\u{FFFC}';

  final ComposerAttachBbCodeGrammar grammar;

  /// 返回把文档里所有字面 attach 代码换成 embed 的 delta；无可提升时返回 null。
  ///
  /// 光标不需要调用方处理：`QuillController.compose` 会用
  /// `Delta.transformPosition` 把落在 token 内部或末尾的光标迁移到 embed 之后。
  Delta? buildPromotion(Document document) {
    final runs = _logicalRuns(document);
    final logicalText = runs.map((run) => run.text).join();
    final matches = grammar.scan(logicalText);
    if (matches.isEmpty) {
      return null;
    }

    final delta = Delta();
    var offset = 0;
    for (final match in matches) {
      if (match.start > offset) {
        delta.retain(match.start - offset);
      }
      delta.delete(match.length);
      // 继承 token 起点的行内样式，让 `[b][attach]1[/attach][/b]` 提升后
      // 编码回去仍然带着加粗。
      delta.insert(
        composerQuillAttachEmbedData(match.aid, match.kind),
        _attributesAt(runs, match.start),
      );
      offset = match.end;
    }
    return delta;
  }

  List<_LogicalRun> _logicalRuns(Document document) {
    final runs = <_LogicalRun>[];
    var offset = 0;
    for (final operation in document.toDelta().toList()) {
      if (!operation.isInsert) {
        continue;
      }
      final data = operation.data;
      final text = data is String ? data : embedPlaceholder;
      runs.add(
        _LogicalRun(
          start: offset,
          text: text,
          attributes: operation.attributes,
        ),
      );
      offset += text.length;
    }
    return runs;
  }

  Map<String, dynamic>? _attributesAt(List<_LogicalRun> runs, int offset) {
    for (final run in runs) {
      if (offset >= run.start && offset < run.start + run.text.length) {
        return run.attributes;
      }
    }
    return null;
  }
}

class _LogicalRun {
  const _LogicalRun({
    required this.start,
    required this.text,
    required this.attributes,
  });

  final int start;
  final String text;
  final Map<String, dynamic>? attributes;
}
