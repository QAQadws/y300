import 'package:flutter/material.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/presentation/widgets/composer_anchored_dropdown.dart';
import 'package:y300/l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);
    return ComposerAnchoredDropdown<NewThreadSpecial>(
      anchorKey: widgetKey,
      summaryKey: summaryKey,
      label: l10n.postingThreadKind,
      value: special,
      valueLabelBuilder: (value) => _labelForSpecial(l10n, value),
      items: [
        ComposerDropdownItem<NewThreadSpecial>(
          key: normalItemKey,
          value: NewThreadSpecial.normal,
          label: l10n.postingNormalThread,
        ),
        ComposerDropdownItem<NewThreadSpecial>(
          key: pollItemKey,
          value: NewThreadSpecial.poll,
          label: l10n.postingPoll,
        ),
      ],
      onSelected: onChanged,
      enabled: enabled,
    );
  }

  String _labelForSpecial(AppLocalizations l10n, NewThreadSpecial value) {
    return switch (value) {
      NewThreadSpecial.normal => l10n.postingNormalThread,
      NewThreadSpecial.poll => l10n.postingPoll,
    };
  }
}
