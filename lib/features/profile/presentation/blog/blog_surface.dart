import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

/// Shared reading surface for summaries, articles, comments and draft previews.
class BlogSurface extends StatelessWidget {
  const BlogSurface({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final native = Theme.of(context).y300NativeContent;
    final radius = BorderRadius.circular(12);
    final content = Padding(padding: const EdgeInsets.all(12), child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: ForumNativeSurfaceShadows.card(native.stateLayer),
      ),
      child: Material(
        color: native.card,
        elevation: 0,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: radius, child: content),
      ),
    );
  }
}
