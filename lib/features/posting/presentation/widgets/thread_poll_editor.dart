import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 投票编辑器。
///
/// 仅当 `state.special == poll` 时被 page 渲染。组件内部不持有业务态：
/// - 选项列表用 `widget.poll.options` 直接渲染；增删/编辑都通过 callback
///   把"完整下一份 options"上抛，让 controller 做规整。
/// - 多选 / 截止天数 / 公开投票人 / 投票后才显示结果各自独立 callback。
///
/// 这种"零本地状态"的写法让 widget 易测：单测里直接 pump 不同 poll 实例，
/// 验证渲染与 callback 行为即可。
class ThreadPollEditor extends StatelessWidget {
  const ThreadPollEditor({
    super.key,
    required this.poll,
    required this.onOptionsChanged,
    required this.onMultipleChanged,
    required this.onMaxChoicesChanged,
    required this.onExpirationDaysChanged,
    required this.onOvertChanged,
    required this.onVisibilityPollChanged,
    this.enabled = true,
    this.containerKey,
    this.optionFieldKeyBuilder,
    this.optionRemoveKeyBuilder,
    this.addOptionButtonKey,
    this.multipleSwitchKey,
    this.maxChoicesFieldKey,
    this.expirationFieldKey,
    this.overtSwitchKey,
    this.visibilityPollSwitchKey,
  });

  final NewThreadPollDraft poll;
  final ValueChanged<List<String>> onOptionsChanged;
  final ValueChanged<bool> onMultipleChanged;
  final ValueChanged<int> onMaxChoicesChanged;
  final ValueChanged<int> onExpirationDaysChanged;
  final ValueChanged<bool> onOvertChanged;
  final ValueChanged<bool> onVisibilityPollChanged;
  final bool enabled;

  final Key? containerKey;
  final Key Function(int index)? optionFieldKeyBuilder;
  final Key Function(int index)? optionRemoveKeyBuilder;
  final Key? addOptionButtonKey;
  final Key? multipleSwitchKey;
  final Key? maxChoicesFieldKey;
  final Key? expirationFieldKey;
  final Key? overtSwitchKey;
  final Key? visibilityPollSwitchKey;

  void _updateOption(int index, String value) {
    final next = List<String>.from(poll.options);
    next[index] = value;
    onOptionsChanged(next);
  }

  void _removeOption(int index) {
    if (index < 0 || index >= poll.options.length) return;
    final next = List<String>.from(poll.options)..removeAt(index);
    onOptionsChanged(next);
  }

  void _addOption() {
    if (poll.options.length >= NewThreadPollValidation.maxOptions) return;
    final next = List<String>.from(poll.options)..add('');
    onOptionsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final canAddMore = poll.options.length < NewThreadPollValidation.maxOptions;
    return Container(
      key: containerKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.how_to_vote_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(l10n.postingPollConfig, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.postingPollConstraints(
              NewThreadPollValidation.minOptions,
              NewThreadPollValidation.maxOptions,
              NewThreadPollValidation.maxOptionLength,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < poll.options.length; i += 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text('${i + 1}.', style: theme.textTheme.bodyMedium),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: optionFieldKeyBuilder?.call(i),
                      enabled: enabled,
                      initialValue: poll.options[i],
                      onChanged: (value) => _updateOption(i, value),
                      decoration: InputDecoration(
                        hintText: l10n.postingPollOption(i + 1),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          NewThreadPollValidation.maxOptionLength + 4,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: optionRemoveKeyBuilder?.call(i),
                    onPressed: enabled ? () => _removeOption(i) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: l10n.postingPollRemoveOption,
                  ),
                ],
              ),
            ),
          if (canAddMore)
            TextButton.icon(
              key: addOptionButtonKey,
              onPressed: enabled ? _addOption : null,
              icon: const Icon(Icons.add_circle_outline),
              label: Text(l10n.postingPollAddOption),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            key: multipleSwitchKey,
            value: poll.multiple,
            onChanged: enabled ? onMultipleChanged : null,
            title: Text(l10n.postingPollMultiple),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          if (poll.multiple)
            _MaxChoicesField(
              fieldKey: maxChoicesFieldKey,
              initial: poll.maxChoices,
              optionsCount: poll.options.length,
              enabled: enabled,
              onChanged: onMaxChoicesChanged,
            ),
          const SizedBox(height: 8),
          _NumberField(
            fieldKey: expirationFieldKey,
            label: l10n.postingPollDeadline,
            initial: poll.expirationDays,
            min: 0,
            max: 365,
            enabled: enabled,
            onChanged: onExpirationDaysChanged,
          ),
          SwitchListTile(
            key: overtSwitchKey,
            value: poll.overt,
            onChanged: enabled ? onOvertChanged : null,
            title: Text(l10n.postingPollPublicVoters),
            subtitle: Text(l10n.postingPollPublicVotersDescription),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          SwitchListTile(
            key: visibilityPollSwitchKey,
            value: poll.visibilityPoll,
            onChanged: enabled ? onVisibilityPollChanged : null,
            title: Text(l10n.postingPollShowResultsAfterVote),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _MaxChoicesField extends StatelessWidget {
  const _MaxChoicesField({
    required this.fieldKey,
    required this.initial,
    required this.optionsCount,
    required this.enabled,
    required this.onChanged,
  });

  final Key? fieldKey;
  final int initial;
  final int optionsCount;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final upperBound = optionsCount < 2 ? 2 : optionsCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _NumberField(
        fieldKey: fieldKey,
        label: AppLocalizations.of(context).postingPollMaxChoices(upperBound),
        initial: initial < 2 ? 2 : initial,
        min: 2,
        max: upperBound,
        enabled: enabled,
        onChanged: onChanged,
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.fieldKey,
    required this.label,
    required this.initial,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final Key? fieldKey;
  final String label;
  final int initial;
  final int min;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      enabled: enabled,
      initialValue: initial.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (value) {
        final parsed = int.tryParse(value);
        if (parsed == null) return;
        final clamped = parsed < min ? min : (parsed > max ? max : parsed);
        onChanged(clamped);
      },
    );
  }
}
