import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionAppBar({
    super.key,
    required this.selectedCount,
    required this.l10n,
    required this.onClose,
    required this.onSelectAll,
    required this.onInvertSelection,
  });

  final int selectedCount;
  final AppLocalizations l10n;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onInvertSelection;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      key: const Key('selection-app-bar'),
      leading: IconButton(
        key: const Key('selection-app-bar-close'),
        tooltip: l10n.librarySelectionExit,
        icon: const Icon(Icons.close),
        onPressed: onClose,
      ),
      title: Text(
        l10n.librarySelectionSelectedCount(selectedCount),
        key: const Key('selection-app-bar-title'),
      ),
      actions: [
        IconButton(
          key: const Key('selection-app-bar-select-all'),
          tooltip: l10n.librarySelectionSelectAll,
          icon: const Icon(Icons.select_all),
          onPressed: onSelectAll,
        ),
        IconButton(
          key: const Key('selection-app-bar-invert'),
          tooltip: l10n.librarySelectionInvert,
          icon: const Icon(Icons.flip_to_back),
          onPressed: onInvertSelection,
        ),
      ],
    );
  }
}
