import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/l10n/app_localizations.dart';

/// The selection belongs to the caller; closing the sheet changes no state.
class ComposerReadAccessTile extends StatelessWidget {
  const ComposerReadAccessTile({
    super.key,
    required this.access,
    required this.selectedValue,
    required this.onChanged,
    this.enabled = true,
    this.preservingExisting = false,
  });

  final ThreadReadAccess access;
  final int? selectedValue;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final bool preservingExisting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = selectedValue;
    final selectedOption = access.options
        .where((option) => option.value == value)
        .firstOrNull;
    final canKeep = preservingExisting && value == access.currentValue;
    final valid =
        value != null &&
        (access.allows(value) || canKeep || (!access.canModify && value == 0));
    // A restored restricted draft may lose the account's setting capability.
    // Only an explicit choice may release that restriction.
    final canReleaseInvalidDraft =
        !preservingExisting &&
        !access.canModify &&
        value != 0 &&
        (access.currentValue ?? 0) == 0;
    final selectable = access.canModify || canReleaseInvalidDraft;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.lock_outline),
      title: Text(l10n.composerReadAccess),
      subtitle: Text(
        [
          if (value == null)
            l10n.composerReadAccessUnknown
          else if (canKeep && !access.allows(value))
            l10n.composerReadAccessKeep(value)
          else
            readAccessLabel(l10n, value),
          if (value != 0 &&
              value != 255 &&
              selectedOption?.groupNames.isNotEmpty == true)
            selectedOption!.groupNames.join(' / '),
          if (value != null && !valid) l10n.composerReadAccessInvalid,
          if (!access.canModify) l10n.composerReadAccessUnavailable,
        ].join('\n'),
      ),
      trailing: selectable ? const Icon(Icons.chevron_right) : null,
      onTap: !enabled || !selectable
          ? null
          : () async {
              final options = [
                if (canReleaseInvalidDraft)
                  const ThreadReadAccessOption(value: 0),
                if (!canReleaseInvalidDraft) ...access.options,
              ];
              final keep =
                  preservingExisting &&
                  access.currentValue != null &&
                  !access.options.any(
                    (option) => option.value == access.currentValue,
                  );
              final result = await showModalBottomSheet<int>(
                context: context,
                isScrollControlled: true,
                builder: (context) => SafeArea(
                  child: DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: 0.55,
                    maxChildSize: 0.85,
                    builder: (context, scrollController) => ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          l10n.composerReadAccess,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (keep)
                          _choice(
                            context,
                            value: access.currentValue!,
                            title: l10n.composerReadAccessKeep(
                              access.currentValue!,
                            ),
                          ),
                        for (final option in options)
                          _choice(
                            context,
                            value: option.value,
                            title: readAccessLabel(l10n, option.value),
                            subtitle: option.value == 0 || option.value == 255
                                ? null
                                : option.groupNames.join(' / '),
                          ),
                      ],
                    ),
                  ),
                ),
              );
              if (result != null && context.mounted) onChanged(result);
            },
    );
  }

  Widget _choice(
    BuildContext context, {
    required int value,
    required String title,
    String? subtitle,
  }) => ListTile(
    key: ValueKey('read-access-option-$value'),
    title: Text(title),
    subtitle: subtitle == null || subtitle.isEmpty ? null : Text(subtitle),
    trailing: Icon(
      value == selectedValue
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked,
    ),
    selected: value == selectedValue,
    onTap: () => Navigator.of(context).pop(value),
  );
}

String readAccessLabel(AppLocalizations l10n, int value) => switch (value) {
  0 => l10n.composerReadAccessUnlimited,
  255 => l10n.composerReadAccessHighest,
  _ => l10n.composerReadAccessLevel(value),
};
