import 'package:flutter/material.dart';

/// AsyncNotifier 加载草稿失败时展示的错误兜底视图。
///
/// 比 reply 私有 `_ReplyComposerErrorView` 多支持一个 widget key 注入入口，
/// 便于发帖页与回复页保留各自的查询入口。
class ComposerLoadErrorView extends StatelessWidget {
  const ComposerLoadErrorView({super.key, required this.message, this.textKey});

  final String message;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, key: textKey, textAlign: TextAlign.center),
      ),
    );
  }
}
