import 'package:flutter/material.dart';

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
    if (inShelf) {
      return FilledButton.icon(
        key: const Key('comic-in-shelf-button'),
        onPressed: onPressed,
        icon: const Icon(Icons.bookmark_added_outlined),
        label: const Text('已在书架'),
      );
    }

    return FilledButton.icon(
      key: const Key('comic-add-to-shelf-button'),
      onPressed: onPressed,
      icon: const Icon(Icons.bookmark_add_outlined),
      label: const Text('加入书架'),
    );
  }
}
