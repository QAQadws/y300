import 'package:flutter/material.dart';
import 'package:flutter_bbcode/flutter_bbcode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final forumBbCodeRendererProvider = Provider<ForumBbCodeRenderer>((_) {
  return const FlutterBbCodeForumRenderer();
});

abstract class ForumBbCodeRenderer {
  const ForumBbCodeRenderer();

  Widget buildPreview(BuildContext context, String source);
}

class FlutterBbCodeForumRenderer extends ForumBbCodeRenderer {
  const FlutterBbCodeForumRenderer();

  @override
  Widget buildPreview(BuildContext context, String source) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ) ??
        TextStyle(color: colorScheme.onSurface);
    final stylesheet = defaultBBStylesheet(textStyle: textStyle);
    stylesheet.removeTag('img');

    return BBCodeText(
      data: source,
      stylesheet: stylesheet,
      errorBuilder: (_, _, _) => Text(source, style: textStyle),
    );
  }
}
