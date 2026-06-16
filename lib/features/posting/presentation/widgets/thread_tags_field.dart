import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 主题标签 chip 输入框。
///
/// 设计取舍：
/// - 用 [Wrap] 把已确认的 tags 渲染成 [InputChip]，末尾跟一个轻量
///   [TextField] 收尾，让"键入 + 已有 chip"在视觉上是一行。
/// - 确认 tag 的触发：回车（`onSubmitted`）或键入英文/中文逗号（`,` / `，`）。
///   两种触发都集中在 `_commit` 这一处，避免行为漂移。
/// - 不在内部维护"已确认 tags"——上层 controller 调 normalizer 后通过
///   [tags] 传回来，widget 只反映；内部仅维护"待确认输入"那个 TextField 的
///   text，避免双源真理。
/// - 防重 / 防超长 / 防超量交给 controller / normalizer 兜底；UI 层对
///   `_commit` 的输入做最浅的 trim & 长度过滤，避免把一长串无效字符上抛。
///
/// `enabled = false` 时 chip 删除按钮、TextField 都禁用。
class ThreadTagsField extends StatefulWidget {
  const ThreadTagsField({
    super.key,
    required this.tags,
    required this.onChanged,
    this.enabled = true,
    this.maxTags = 5,
    this.maxTagLength = 16,
    this.containerKey,
    this.inputFieldKey,
    this.chipKeyBuilder,
    this.removeButtonKeyBuilder,
    this.title = '主题标签',
    this.hintText = '输入标签，回车或英文逗号确认',
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  final int maxTags;
  final int maxTagLength;
  final Key? containerKey;
  final Key? inputFieldKey;
  final Key Function(String tag, int index)? chipKeyBuilder;
  final Key Function(String tag, int index)? removeButtonKeyBuilder;
  final String title;
  final String hintText;

  @override
  State<ThreadTagsField> createState() => _ThreadTagsFieldState();
}

class _ThreadTagsFieldState extends State<ThreadTagsField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    // 中英文逗号都视作"确认上一个 tag"。
    final separatorIndex = _findSeparator(value);
    if (separatorIndex == -1) return;
    final candidate = value.substring(0, separatorIndex);
    final tail = value.substring(separatorIndex + 1);
    _commit(candidate, residual: tail);
  }

  int _findSeparator(String value) {
    for (var i = 0; i < value.length; i += 1) {
      final ch = value[i];
      if (ch == ',' || ch == '，') return i;
    }
    return -1;
  }

  void _onSubmitted(String value) {
    _commit(value);
  }

  /// 把 [candidate] trim 后追加到 tags；[residual] 写回 TextField 留给用户继续输入。
  void _commit(String candidate, {String residual = ''}) {
    final trimmed = candidate.trim();
    // 空字符串、超长、已存在的全部丢弃，但 TextField 仍要清掉，否则光标停在
    // 用户键入的逗号上等下次 `_commit` 死循环。
    if (trimmed.isEmpty ||
        trimmed.length > widget.maxTagLength ||
        widget.tags.contains(trimmed) ||
        widget.tags.length >= widget.maxTags) {
      _controller.value = TextEditingValue(
        text: residual,
        selection: TextSelection.collapsed(offset: residual.length),
      );
      return;
    }
    final next = List<String>.from(widget.tags)..add(trimmed);
    widget.onChanged(next);
    _controller.value = TextEditingValue(
      text: residual,
      selection: TextSelection.collapsed(offset: residual.length),
    );
  }

  void _removeAt(int index) {
    if (!widget.enabled) return;
    if (index < 0 || index >= widget.tags.length) return;
    final next = List<String>.from(widget.tags)..removeAt(index);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAddMore = widget.tags.length < widget.maxTags;
    return Column(
      key: widget.containerKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            // hintText 由内部 TextField 接管，外层只画边框。
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < widget.tags.length; i += 1)
                InputChip(
                  key: widget.chipKeyBuilder?.call(widget.tags[i], i),
                  label: Text(widget.tags[i]),
                  onDeleted: widget.enabled ? () => _removeAt(i) : null,
                  deleteButtonTooltipMessage: widget.enabled ? '删除标签' : null,
                  // deleteIcon 依赖默认实现；若需要测试单独 key，
                  // 改成 [GestureDetector] 包裹一个自定义 Icon 即可。
                ),
              if (canAddMore)
                _ChipInputField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  hintText: widget.hintText,
                  inputFieldKey: widget.inputFieldKey,
                  onChanged: _onTextChanged,
                  onSubmitted: _onSubmitted,
                  maxTagLength: widget.maxTagLength,
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '最多 ${widget.maxTags} 个；单个标签 ≤ ${widget.maxTagLength} 字符',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 内嵌在 [Wrap] 末尾的轻量输入框。
///
/// 设宽度上限避免 Wrap 把单行 TextField 撑成"独占一行"看起来像两行；
/// `IntrinsicWidth` 让光标始终贴着已输入文字。
class _ChipInputField extends StatelessWidget {
  const _ChipInputField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hintText,
    required this.inputFieldKey,
    required this.onChanged,
    required this.onSubmitted,
    required this.maxTagLength,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String hintText;
  final Key? inputFieldKey;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final int maxTagLength;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
      child: TextField(
        key: inputFieldKey,
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.done,
        maxLines: 1,
        // 截到 maxTagLength + 2，留给逗号/换行触发器，最终 commit 还会再过滤一次。
        inputFormatters: [
          LengthLimitingTextInputFormatter(maxTagLength + 2),
        ],
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: hintText,
        ),
      ),
    );
  }
}
