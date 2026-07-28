import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/presentation/selection/selection_action_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    required this.actions,
    required this.l10n,
    required this.onActionTap,
  });

  final List<SelectionAction> actions;
  final AppLocalizations l10n;
  final Future<void> Function(SelectionAction action) onActionTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('selection-action-bar'),
      color: colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Row(
            children: actions
                .map((action) {
                  final foregroundColor = action.destructive
                      ? colorScheme.error
                      : null;
                  return Expanded(
                    child: Center(
                      child: IconButton(
                        key: ValueKey<String>('selection-action-${action.id}'),
                        tooltip: SelectionActionTextResolver.label(
                          l10n,
                          action.id,
                        ),
                        icon: Icon(action.icon, color: foregroundColor),
                        onPressed: () {
                          onActionTap(action);
                        },
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}
