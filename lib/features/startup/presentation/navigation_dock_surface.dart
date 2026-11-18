import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// The scroll-edge fade is painted before the dock samples the live backdrop.
class NavigationDockSurface extends StatelessWidget {
  const NavigationDockSurface({
    required this.dockRect,
    required this.press,
    required this.fadePage,
    super.key,
  });

  final Rect dockRect;
  final double press;
  final bool fadePage;

  static final _pageBlur = ui.ImageFilter.blur(sigmaX: 5.5, sigmaY: 5.5);
  static const _pageFeather = DecoratedBox(
    decoration: BoxDecoration(
      backgroundBlendMode: BlendMode.dstIn,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment(0, 0.93),
        stops: [0, 0.24, 0.46, 0.62, 0.79, 1],
        colors: [
          Colors.transparent,
          Color(0x05000000),
          Color(0x24000000),
          Color(0x88000000),
          Color(0xEC000000),
          Colors.black,
        ],
      ),
    ),
    child: SizedBox.expand(),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final dark = colors.brightness == Brightness.dark;
    final material = LiquidGlassSettings.ios26Indicator.copyWith(
      bodyMode: GlassBodyMode.clear,
      glassColor: colors.surface.withValues(alpha: dark ? 0.34 : 0.25),
      thickness: 21,
      lightIntensity: 0.08,
      ambientStrength: 0,
      fresnelStrength: 0.05,
      rimLight: 0,
      shadowElevation: 0,
    );
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (fadePage && !highContrast)
            ClipRect(
              child: BackdropFilter(filter: _pageBlur, child: _pageFeather),
            ),
          Positioned.fromRect(
            rect: dockRect,
            child: Transform.translate(
              offset: Offset(0, -0.5 * press),
              child: Transform.scale(
                scaleX: 1 + 0.009 * press,
                scaleY: 1 + 2.9 * press / dockRect.height,
                child: highContrast
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(
                            dockRect.height / 2,
                          ),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                      )
                    : AdaptiveGlass(
                        quality: GlassQuality.premium,
                        shape: LiquidRoundedRectangle(
                          borderRadius: dockRect.height / 2,
                        ),
                        settings: material,
                        clipExpansion: const EdgeInsets.all(3),
                        child: const SizedBox.expand(),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
