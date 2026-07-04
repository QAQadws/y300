import 'package:flutter/material.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/presentation/widgets/composer_anchored_dropdown.dart';

/// 普通帖 / 投票 切换器。
///
/// 单一职责：把当前 [NewThreadSpecial] 渲染成紧凑下拉，切换时通过
/// [onChanged] 上抛——是否清空 poll、要不要给空 draft 都由 controller 决定，
/// widget 内部不持有业务状态。
class ThreadSpecialSwitch extends StatelessWidget {
  const ThreadSpecialSwitch({
    super.key,
    required this.special,
    required this.onChanged,
    this.enabled = true,
    this.widgetKey,
    this.summaryKey,
    this.normalItemKey,
    this.pollItemKey,
  });

  final NewThreadSpecial special;
  final ValueChanged<NewThreadSpecial> onChanged;
  final bool enabled;
  final Key? widgetKey;
  final Key? summaryKey;
  final Key? normalItemKey;
  final Key? pollItemKey;

  @override
  Widget build(BuildContext context) {
    return ComposerAnchoredDropdown<NewThreadSpecial>(
      anchorKey: widgetKey,
      summaryKey: summaryKey,
      label: '帖子类型',
      value: special,
      valueLabelBuilder: _labelForSpecial,
      items: [
        ComposerDropdownItem<NewThreadSpecial>(
          key: normalItemKey,
          value: NewThreadSpecial.normal,
          label: '普通帖',
        ),
        ComposerDropdownItem<NewThreadSpecial>(
          key: pollItemKey,
          value: NewThreadSpecial.poll,
          label: '投票',
        ),
      ],
      onSelected: onChanged,
      enabled: enabled,
    );
  }

  String _labelForSpecial(NewThreadSpecial value) {
    return switch (value) {
      NewThreadSpecial.normal => '普通帖',
      NewThreadSpecial.poll => '投票',
    };
  }
}
