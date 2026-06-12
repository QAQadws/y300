import 'package:flutter/material.dart';

/// 顶部"已恢复未发送草稿"提示条。
///
/// reply 与（后续阶段的）发帖页共用，仅传 widget key 来保留各自的稳定查询入口。
class ComposerRestoredDraftBanner extends StatelessWidget {
  const ComposerRestoredDraftBanner({
    super.key,
    this.text = '已恢复未发送草稿',
    this.textKey,
  });

  final String text;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, key: textKey),
      ),
    );
  }
}
