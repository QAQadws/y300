import 'package:flutter/material.dart';
import 'package:y300/features/reply/presentation/bbcode/forum_bbcode_renderer.dart';

class BbCodePreviewPanel extends StatelessWidget {
  const BbCodePreviewPanel({
    super.key,
    required this.source,
    required this.renderer,
  });

  final String source;
  final ForumBbCodeRenderer renderer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: const Key('reply-composer-bbcode-preview-panel'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: source.trim().isEmpty
          ? const SizedBox(
              key: Key('reply-composer-bbcode-preview-empty'),
              height: 24,
            )
          : renderer.buildPreview(context, source),
    );
  }
}
