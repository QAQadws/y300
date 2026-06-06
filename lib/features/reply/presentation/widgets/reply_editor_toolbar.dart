import 'package:flutter/material.dart';

class ReplyEditorToolbar extends StatelessWidget {
  const ReplyEditorToolbar({
    super.key,
    required this.onStickerPressed,
    this.enabled = true,
  });

  final VoidCallback onStickerPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const Key('reply-composer-sticker-button'),
          tooltip: '表情',
          onPressed: enabled ? onStickerPressed : null,
          icon: const Icon(Icons.mood),
        ),
      ],
    );
  }
}
