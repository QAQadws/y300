import 'package:flutter/material.dart';

class ComposerDropdownItem<T> {
  const ComposerDropdownItem({
    required this.value,
    required this.label,
    this.key,
  });

  final T value;
  final String label;
  final Key? key;
}

/// Compact anchored dropdown used by the posting composer form.
///
/// This mirrors the native forum display filter menu: a fixed-height anchor,
/// a bounded overlay panel, and a rotating arrow rather than a full-width
/// Material popup menu.
class ComposerAnchoredDropdown<T> extends StatefulWidget {
  const ComposerAnchoredDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onSelected,
    required this.valueLabelBuilder,
    this.enabled = true,
    this.anchorKey,
    this.summaryKey,
    this.panelKey,
  });

  final String label;
  final T value;
  final List<ComposerDropdownItem<T>> items;
  final ValueChanged<T> onSelected;
  final String Function(T value) valueLabelBuilder;
  final bool enabled;
  final Key? anchorKey;
  final Key? summaryKey;
  final Key? panelKey;

  @override
  State<ComposerAnchoredDropdown<T>> createState() =>
      _ComposerAnchoredDropdownState<T>();
}

class _ComposerAnchoredDropdownState<T>
    extends State<ComposerAnchoredDropdown<T>> {
  static const double _anchorHeight = 44;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isMenuOpen = false;

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _toggleMenu() {
    if (!widget.enabled) {
      return;
    }
    if (_overlayEntry != null) {
      _removeOverlay();
      return;
    }
    _showOverlay();
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return;
    }
    _setMenuOpen(true);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return _ComposerAnchoredDropdownOverlay<T>(
          layerLink: _layerLink,
          anchorSize: renderBox.size,
          items: widget.items,
          selectedValue: widget.value,
          panelKey: widget.panelKey,
          onDismiss: _removeOverlay,
          onSelected: (value) {
            _removeOverlay();
            widget.onSelected(value);
          },
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      _setMenuOpen(false);
    }
  }

  void _setMenuOpen(bool value) {
    if (_isMenuOpen == value) {
      return;
    }
    setState(() {
      _isMenuOpen = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = widget.enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    final outline = theme.colorScheme.outlineVariant;
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        key: widget.anchorKey,
        height: _anchorHeight,
        width: double.infinity,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggleMenu,
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: outline),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.valueLabelBuilder(widget.value),
                            key: widget.summaryKey,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: foreground,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    _ComposerDropdownArrow(
                      isExpanded: _isMenuOpen,
                      color: foreground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerAnchoredDropdownOverlay<T> extends StatelessWidget {
  const _ComposerAnchoredDropdownOverlay({
    required this.layerLink,
    required this.anchorSize,
    required this.items,
    required this.selectedValue,
    required this.onDismiss,
    required this.onSelected,
    this.panelKey,
  });

  static const double _itemHeight = 44;
  static const double _maxPanelHeight = 264;

  final LayerLink layerLink;
  final Size anchorSize;
  final List<ComposerDropdownItem<T>> items;
  final T selectedValue;
  final VoidCallback onDismiss;
  final ValueChanged<T> onSelected;
  final Key? panelKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menuHeight = (items.length * _itemHeight)
        .clamp(0.0, _maxPanelHeight)
        .toDouble();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  alignment: Alignment.topLeft,
                  scaleY: value,
                  child: child,
                ),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: anchorSize.width,
                  maxWidth: anchorSize.width,
                  maxHeight: _maxPanelHeight,
                ),
                child: DecoratedBox(
                  key: panelKey,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: anchorSize.width,
                      height: menuHeight,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemExtent: _itemHeight,
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isSelected = item.value == selectedValue;
                          return InkWell(
                            key: item.key,
                            onTap: isSelected
                                ? null
                                : () => onSelected(item.value),
                            child: Center(
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ComposerDropdownArrow extends StatelessWidget {
  const _ComposerDropdownArrow({required this.isExpanded, required this.color});

  final bool isExpanded;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: isExpanded ? 0.5 : 0),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      builder: (context, turns, child) {
        return RotationTransition(
          turns: AlwaysStoppedAnimation<double>(turns),
          child: child,
        );
      },
      child: Icon(Icons.keyboard_arrow_down, color: color),
    );
  }
}
