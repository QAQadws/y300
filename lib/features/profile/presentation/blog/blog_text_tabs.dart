import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';

class BlogTextTab<T> {
  const BlogTextTab({
    required this.value,
    required this.label,
    required this.key,
    this.description,
  });

  final T value;
  final String label;
  final Key key;
  final String? description;
}

/// Compact navigation shared by blog ordering and category filters.
class BlogTextTabs<T> extends StatefulWidget {
  const BlogTextTabs({
    super.key,
    required this.tabs,
    required this.selectedValue,
    required this.onSelected,
  });

  final List<BlogTextTab<T>> tabs;
  final T selectedValue;
  final ValueChanged<T> onSelected;

  @override
  State<BlogTextTabs<T>> createState() => _BlogTextTabsState<T>();
}

class _BlogTextTabsState<T> extends State<BlogTextTabs<T>> {
  final _selectedKey = GlobalKey();
  bool _revealScheduled = false;
  (double, TextScaler, TextDirection)? _layout;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _revealSelection();
  }

  @override
  void didUpdateWidget(covariant BlogTextTabs<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedValue != widget.selectedValue ||
        oldWidget.tabs.length != widget.tabs.length ||
        oldWidget.tabs.indexed.any((entry) {
          final previous = entry.$2;
          final current = widget.tabs[entry.$1];
          return previous.value != current.value ||
              previous.label != current.label;
        })) {
      _revealSelection();
    }
  }

  void _revealSelection() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted) return;
      final selectedContext = _selectedKey.currentContext;
      final selectedBox = selectedContext?.findRenderObject();
      if (selectedContext == null || selectedBox is! RenderBox) return;
      final scrollable = Scrollable.of(selectedContext);
      final viewport = scrollable.context.findRenderObject();
      if (viewport is! RenderBox || !scrollable.position.hasContentDimensions) {
        return;
      }
      final left = selectedBox
          .localToGlobal(Offset.zero, ancestor: viewport)
          .dx;
      if (left >= 0 && left + selectedBox.size.width <= viewport.size.width) {
        return;
      }
      // Reveal deep-linked selections without resetting a user's manual scroll
      // whenever a loading state or the surrounding feed rebuilds.
      scrollable.position.ensureVisible(
        selectedBox,
        alignment: selectedBox.size.width > viewport.size.width ? 0 : 0.5,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = (
          constraints.maxWidth,
          MediaQuery.textScalerOf(context),
          Directionality.of(context),
        );
        if (_layout != layout) {
          _layout = layout;
          _revealSelection();
        }
        return ColoredBox(
          color: palette.background,
          child: SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, tab) in widget.tabs.indexed) ...[
                    if (index > 0)
                      SizedBox(
                        width: 1,
                        height: 14,
                        child: ColoredBox(
                          color: palette.muted.withValues(alpha: 0.3),
                        ),
                      ),
                    KeyedSubtree(
                      key: tab.value == widget.selectedValue
                          ? _selectedKey
                          : null,
                      child: Semantics(
                        key: tab.key,
                        selected: tab.value == widget.selectedValue,
                        button: true,
                        inMutuallyExclusiveGroup: true,
                        child: Tooltip(
                          message: tab.description ?? tab.label,
                          excludeFromSemantics: true,
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              onTap: () => widget.onSelected(tab.value),
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 64,
                                  minHeight: 48,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Center(
                                    widthFactor: 1,
                                    heightFactor: 1,
                                    child: Text(
                                      tab.label,
                                      maxLines: 1,
                                      softWrap: false,
                                      semanticsLabel: tab.description,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color:
                                                tab.value ==
                                                    widget.selectedValue
                                                ? palette.accent
                                                : palette.muted,
                                            fontWeight:
                                                tab.value ==
                                                    widget.selectedValue
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
