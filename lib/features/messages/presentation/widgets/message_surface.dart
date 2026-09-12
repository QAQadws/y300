import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

/// Message surfaces follow forum cards without adding Material's own elevation.
class MessageSurface extends StatelessWidget {
  const MessageSurface({
    super.key,
    required this.child,
    this.color,
    this.onTap,
  });

  final Widget child;
  final Color? color;
  final VoidCallback? onTap;

  static const borderRadius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).y300NativeContent;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
      ),
      child: Material(
        color: color ?? palette.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? child
            : InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                overlayColor: WidgetStatePropertyAll(palette.subtleStateLayer),
                child: child,
              ),
      ),
    );
  }
}
