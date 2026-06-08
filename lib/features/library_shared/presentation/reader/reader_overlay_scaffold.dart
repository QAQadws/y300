import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_bottom_overlay_panel.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_tap_zones.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_top_overlay_bar.dart';

class ReaderOverlayScaffold extends StatefulWidget {
  const ReaderOverlayScaffold({
    super.key,
    required this.topBar,
    required this.bottomBar,
    required this.child,
    this.onLeftTap,
    this.onCenterTap,
    this.onRightTap,
    this.menuInitiallyVisible = false,
    this.tapZonesEnabled = true,
    this.bottomSafeFraction = 0,
    this.animationDuration = const Duration(milliseconds: 240),
  });

  final ReaderTopBarConfig topBar;
  final ReaderBottomBarConfig bottomBar;
  final Widget child;
  final VoidCallback? onLeftTap;
  final VoidCallback? onCenterTap;
  final VoidCallback? onRightTap;
  final bool menuInitiallyVisible;
  final bool tapZonesEnabled;
  final double bottomSafeFraction;
  final Duration animationDuration;

  @override
  State<ReaderOverlayScaffold> createState() => _ReaderOverlayScaffoldState();
}

class _ReaderOverlayScaffoldState extends State<ReaderOverlayScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<Offset> _topSlideAnimation;
  late final Animation<Offset> _bottomSlideAnimation;
  late bool _isMenuVisible;

  @override
  void initState() {
    super.initState();
    _isMenuVisible = widget.menuInitiallyVisible;
    _animationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
      value: _isMenuVisible ? 1 : 0,
    );
    final curve = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _topSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(curve);
    _bottomSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(curve);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const Key('shared-reader-overlay-scaffold'),
      children: [
        ReaderTapZones(
          enabled: widget.tapZonesEnabled,
          bottomSafeFraction: widget.bottomSafeFraction,
          onCenterTap: _handleCenterTap,
          onLeftTap: widget.onLeftTap,
          onRightTap: widget.onRightTap,
          child: widget.child,
        ),
        Positioned(
          key: const Key('shared-reader-top-overlay'),
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            key: const Key('shared-reader-top-overlay-hit-test-gate'),
            ignoring: !_isMenuVisible,
            child: SlideTransition(
              position: _topSlideAnimation,
              child: ReaderTopOverlayBar(config: widget.topBar),
            ),
          ),
        ),
        Positioned(
          key: const Key('shared-reader-bottom-overlay'),
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            key: const Key('shared-reader-bottom-overlay-hit-test-gate'),
            ignoring: !_isMenuVisible,
            child: SlideTransition(
              position: _bottomSlideAnimation,
              child: ReaderBottomOverlayPanel(config: widget.bottomBar),
            ),
          ),
        ),
      ],
    );
  }

  void _toggleMenu() {
    setState(() {
      _isMenuVisible = !_isMenuVisible;
    });
    if (_isMenuVisible) {
      _animationController.forward();
      return;
    }
    _animationController.reverse();
  }

  void _handleCenterTap() {
    _toggleMenu();
    widget.onCenterTap?.call();
  }
}
