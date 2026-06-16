import 'package:flutter/material.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';

/// 普通帖 / 投票 切换器（SegmentedButton）。
///
/// 单一职责：把当前 [NewThreadSpecial] 渲染成两段式按钮，切换时通过
/// [onChanged] 上抛——是否清空 poll、要不要给空 draft 都由 controller 决定，
/// widget 内部不持有业务状态。
class ThreadSpecialSwitch extends StatelessWidget {
  const ThreadSpecialSwitch({
    super.key,
    required this.special,
    required this.onChanged,
    this.enabled = true,
    this.widgetKey,
  });

  final NewThreadSpecial special;
  final ValueChanged<NewThreadSpecial> onChanged;
  final bool enabled;
  final Key? widgetKey;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<NewThreadSpecial>(
      key: widgetKey,
      segments: const [
        ButtonSegment<NewThreadSpecial>(
          value: NewThreadSpecial.normal,
          label: Text('普通帖'),
          icon: Icon(Icons.article_outlined),
        ),
        ButtonSegment<NewThreadSpecial>(
          value: NewThreadSpecial.poll,
          label: Text('投票'),
          icon: Icon(Icons.how_to_vote_outlined),
        ),
      ],
      selected: <NewThreadSpecial>{special},
      onSelectionChanged: enabled
          ? (selection) {
              if (selection.isEmpty) return;
              onChanged(selection.first);
            }
          : null,
      showSelectedIcon: false,
    );
  }
}
