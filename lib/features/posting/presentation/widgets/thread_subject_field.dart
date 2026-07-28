import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 发帖标题输入框。
///
/// 单独抽出 widget 是为了让 `PostingComposerPage` 的 build 树更扁平，
/// 同时把 widget key（外部测试入口）封装在一处。
///
/// `maxLength` `<=0` 时按"无限制"处理：不渲染计数；否则在右下角展示
/// "当前 / 上限"，超限时染上错误色，与 controller 的 preflight 校验保持一致。
class ThreadSubjectField extends StatelessWidget {
  const ThreadSubjectField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
    this.fieldKey,
    this.hintText,
    this.maxLength = 0,
    this.counterTextKey,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final Key? fieldKey;
  final String? hintText;

  /// `<=0` 表示版块没声明上限，UI 不显示计数。
  final int maxLength;
  final Key? counterTextKey;

  @override
  Widget build(BuildContext context) {
    final hasLimit = maxLength > 0;
    final colorScheme = Theme.of(context).colorScheme;
    final underlineBorder = UnderlineInputBorder(
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );
    final focusedUnderlineBorder = UnderlineInputBorder(
      borderSide: BorderSide(color: colorScheme.primary, width: 2),
    );
    final errorUnderlineBorder = UnderlineInputBorder(
      borderSide: BorderSide(color: colorScheme.error, width: 2),
    );
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      maxLines: 1,
      textInputAction: TextInputAction.next,
      buildCounter: hasLimit ? _buildCounter : _hideDefaultCounter,
      // 仅用 buildCounter 接管计数显示——不传 maxLength，避免 Flutter 把超限
      // 的字符截断。preflight + state.canSubmit 已经在网络/按钮层兜住超限。
      decoration: InputDecoration(
        hintText: hintText ?? AppLocalizations.of(context).postingSubjectHint,
        filled: false,
        border: underlineBorder,
        enabledBorder: underlineBorder,
        focusedBorder: focusedUnderlineBorder,
        errorBorder: errorUnderlineBorder,
        focusedErrorBorder: errorUnderlineBorder,
        disabledBorder: underlineBorder,
      ),
    );
  }

  Widget? _hideDefaultCounter(
    BuildContext context, {
    required int currentLength,
    required int? maxLength,
    required bool isFocused,
  }) {
    return null;
  }

  Widget? _buildCounter(
    BuildContext context, {
    required int currentLength,
    required int? maxLength,
    required bool isFocused,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final exceeded = currentLength > this.maxLength;
    return Text(
      '$currentLength / ${this.maxLength}',
      key: counterTextKey,
      style: TextStyle(
        color: exceeded ? colorScheme.error : colorScheme.onSurfaceVariant,
      ),
    );
  }
}
