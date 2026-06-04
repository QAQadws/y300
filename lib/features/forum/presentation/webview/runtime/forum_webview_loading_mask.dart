import 'package:flutter/material.dart';

class ForumWebViewLoadingMask extends StatelessWidget {
  const ForumWebViewLoadingMask({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surface;
    return IgnorePointer(
      child: ColoredBox(
        key: const Key('forum-webview-loading-mask'),
        color: color,
        child: const SizedBox.expand(),
      ),
    );
  }
}
