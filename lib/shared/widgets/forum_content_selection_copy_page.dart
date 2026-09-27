import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

class ForumContentSelectionCopyPage extends StatelessWidget {
  const ForumContentSelectionCopyPage({
    super.key,
    required this.title,
    this.bodyKey,
    required this.child,
  });

  final String title;
  final Key? bodyKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final native = theme.y300NativeContent;
    return Scaffold(
      backgroundColor: native.background,
      appBar: AppBar(centerTitle: false, title: Text(title)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
          children: [
            Container(
              key: bodyKey,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: native.card,
                borderRadius: BorderRadius.circular(12),
                boxShadow: ForumNativeSurfaceShadows.card(native.stateLayer),
              ),
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: native.body,
                  height: 1.5,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
