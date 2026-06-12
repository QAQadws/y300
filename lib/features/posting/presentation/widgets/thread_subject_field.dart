import 'package:flutter/material.dart';

/// 发帖标题输入框。
///
/// 单独抽出 widget 是为了让 `PostingComposerPage` 的 build 树更扁平，
/// 同时把 widget key（外部测试入口）封装在一处。Phase 5 不做长度限制 /
/// 字数提示，等服务端给出 `forumdisplay.maxsubject` 元数据后再统一接入。
class ThreadSubjectField extends StatelessWidget {
  const ThreadSubjectField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
    this.fieldKey,
    this.hintText = '输入标题',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final Key? fieldKey;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      maxLines: 1,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        hintText: hintText,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
