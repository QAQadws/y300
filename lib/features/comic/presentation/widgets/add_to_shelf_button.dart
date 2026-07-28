import 'package:flutter/material.dart';

import 'package:y300/l10n/app_localizations.dart';

class AddToShelfButton extends StatelessWidget {
  const AddToShelfButton({
    super.key,
    required this.inShelf,
    required this.onPressed,
  });

  final bool inShelf;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (inShelf) {
      return FilledButton.icon(
        key: const Key('comic-in-shelf-button'),
        onPressed: onPressed,
        icon: const Icon(Icons.bookmark_added_outlined),
        label: Text(l10n.comicAlreadyInShelf),
      );
    }

    return FilledButton.icon(
      key: const Key('comic-add-to-shelf-button'),
      onPressed: onPressed,
      icon: const Icon(Icons.bookmark_add_outlined),
      label: Text(l10n.comicAddToShelf),
    );
  }
}
