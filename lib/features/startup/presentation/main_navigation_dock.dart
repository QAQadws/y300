import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:y300/features/startup/presentation/navigation_dock_surface.dart';

class MainNavigationDock extends StatefulWidget {
  const MainNavigationDock({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.fadePage,
    super.key,
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool fadePage;

  static const _iconSize = 20.0;
  static const _iconLabelGap = 3.0;
  // NavigationBar centers the icon in a 32 dp indicator even when transparent.
  static const _iconShift = (32.0 - _iconSize) / 2 - _iconLabelGap;
  static const destinationIconOffset = Offset(0, _iconShift);

  @override
  State<MainNavigationDock> createState() => _MainNavigationDockState();
}

class _MainNavigationDockState extends State<MainNavigationDock>
    with TickerProviderStateMixin {
  static const _preferredItemWidth = 184.0 / 3;
  static const _minimumItemWidth = 48.0;
  static const _sideMargin = 22.0;
  static const _minimumSideMargin = 8.0;
  static const _itemInset = 6.0;
  static const _labelFontSize = 11.0;
  static const _labelLineHeight = 1.1;
  static const _underlineGap = 3.0;
  static const _underlineWidth = 12.0;
  static const _underlineHeight = 1.5;
  static const _labelBottomPadding =
      MainNavigationDock._iconLabelGap +
      _underlineGap +
      _underlineHeight +
      2 * MainNavigationDock._iconShift;

  late final _position = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );
  late final _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final _motion = Listenable.merge([_position, _press]);
  int? _pressedPointer;
  bool _dragging = false;

  @override
  void didUpdateWidget(covariant MainNavigationDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameDestinations = listEquals(
      oldWidget.destinations.map((item) => item.key).toList(),
      widget.destinations.map((item) => item.key).toList(),
    );
    if (!sameDestinations) {
      _dragging = false;
      _position.value = widget.selectedIndex.toDouble();
    } else if (oldWidget.selectedIndex != widget.selectedIndex) {
      _dragging = false;
      _settle(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _position.dispose();
    _press.dispose();
    super.dispose();
  }

  void _settle(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _position.value = index.toDouble();
    } else {
      _position.animateTo(
        index.toDouble(),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _track(double dx, double width, bool rtl) {
    if (width <= 0) return;
    final count = widget.destinations.length;
    final x = rtl ? width - dx : dx;
    _position.value = (x / width * count - 0.5).clamp(0.0, count - 1.0);
  }

  void _release(PointerEvent event) {
    if (event.pointer != _pressedPointer) return;
    _pressedPointer = null;
    _press.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final safe = MediaQuery.paddingOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final count = widget.destinations.length;
    final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    const fadeLead = 16.0;
    const bottomGap = 12.0;
    final bottomInset = ios
        ? math.max(bottomGap, safe.bottom)
        : safe.bottom + bottomGap;
    final labelSize = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: 1.3)
        .scale(_labelFontSize);
    final dockHeight =
        (ios ? 50.0 : 54.0) + math.max(0.0, (labelSize - _labelFontSize) * 2);

    return SizedBox(
      height: fadeLead + dockHeight + bottomInset,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = math.max(
            0.0,
            constraints.maxWidth - safe.horizontal,
          );
          final preferredWidth = _preferredItemWidth * count + 2 * _itemInset;
          final minimumTabRun = _minimumItemWidth * count;
          // Shrink the outside margin before reducing destination hit targets.
          final usableWidth = math.min(
            math.max(0.0, available - 2 * _minimumSideMargin),
            math.max(
              available - 2 * _sideMargin,
              minimumTabRun + 2 * _itemInset,
            ),
          );
          final width = math.min(preferredWidth, usableWidth);
          final inset = ((width - minimumTabRun) / 2).clamp(0.0, _itemInset);
          final tabRun = width - 2 * inset;
          final dockRect = Rect.fromLTWH(
            safe.left + (available - width) / 2,
            fadeLead,
            width,
            dockHeight,
          );
          final underlineTop =
              dockRect.center.dy +
              (MainNavigationDock._iconSize +
                      MainNavigationDock._iconLabelGap +
                      labelSize * _labelLineHeight +
                      _underlineGap -
                      _underlineHeight) /
                  2;
          return AnimatedBuilder(
            animation: _motion,
            child: _buildBar(context, dockHeight),
            builder: (context, bar) {
              final press = reduceMotion ? 0.0 : _press.value;
              final index = rtl ? count - 1 - _position.value : _position.value;
              final underlineX =
                  dockRect.left + inset + tabRun * (index + 0.5) / count;
              return Stack(
                children: [
                  Positioned.fill(
                    child: NavigationDockSurface(
                      dockRect: dockRect,
                      press: press,
                      fadePage: widget.fadePage,
                    ),
                  ),
                  Positioned.fromRect(
                    rect: dockRect,
                    child: Listener(
                      onPointerDown: (event) {
                        if (reduceMotion || _pressedPointer != null) return;
                        _pressedPointer = event.pointer;
                        _press.forward();
                      },
                      onPointerUp: _release,
                      onPointerCancel: _release,
                      child: GestureDetector(
                        excludeFromSemantics: true,
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (event) {
                          _dragging = true;
                          _position.stop();
                          _track(event.localPosition.dx - inset, tabRun, rtl);
                        },
                        onHorizontalDragUpdate: (event) {
                          if (_dragging) {
                            _track(event.localPosition.dx - inset, tabRun, rtl);
                          }
                        },
                        onHorizontalDragEnd: (_) {
                          if (!_dragging) return;
                          _dragging = false;
                          final next = _position.value.round();
                          _settle(next);
                          widget.onSelected(next);
                        },
                        onHorizontalDragCancel: () {
                          if (!_dragging) return;
                          _dragging = false;
                          _settle(widget.selectedIndex);
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: inset),
                          child: bar,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: underlineX - _underlineWidth / 2,
                    width: _underlineWidth,
                    top: underlineTop,
                    height: _underlineHeight,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: colors.primary,
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBar(BuildContext context, double height) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Theme(
      data: theme.copyWith(
        splashFactory: NoSplash.splashFactory,
        navigationBarTheme: NavigationBarTheme.of(context).copyWith(
          iconTheme: WidgetStateProperty.resolveWith((states) {
            return IconThemeData(
              size: MainNavigationDock._iconSize,
              color: states.contains(WidgetState.selected)
                  ? colors.primary
                  : colors.onSurfaceVariant,
            );
          }),
        ),
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        removeRight: true,
        removeBottom: true,
        child: NavigationBar(
          key: const ValueKey<String>('main-shell-navigation-bar'),
          selectedIndex: widget.selectedIndex,
          onDestinationSelected: widget.onSelected,
          destinations: widget.destinations,
          height: height,
          backgroundColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          elevation: 0,
          animationDuration: const Duration(milliseconds: 150),
          labelPadding: const EdgeInsets.only(bottom: _labelBottomPadding),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.focused)
                ? colors.primary.withValues(alpha: 0.10)
                : Colors.transparent;
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: _labelFontSize,
              height: _labelLineHeight,
              color: selected ? colors.primary : colors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
        ),
      ),
    );
  }
}
