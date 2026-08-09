import 'package:flutter/material.dart';

/// A search-mode app bar whose text field is visually part of the toolbar.
///
/// Callers retain ownership of the text and focus controllers so search
/// lifecycle, debouncing, and route behavior stay at the feature boundary.
class InlineSearchAppBar extends StatefulWidget implements PreferredSizeWidget {
  const InlineSearchAppBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.fieldKey,
    required this.hintText,
    required this.clearTooltip,
    required this.onBack,
    this.backButtonKey,
    this.clearButtonKey,
    this.onChanged,
    this.onSubmitted,
    this.onCleared,
    this.submitButtonKey,
    this.submitTooltip,
    this.onSubmit,
    this.submitEnabled = true,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Key fieldKey;
  final String hintText;
  final String clearTooltip;
  final VoidCallback onBack;
  final Key? backButtonKey;
  final Key? clearButtonKey;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onCleared;
  final Key? submitButtonKey;
  final String? submitTooltip;
  final VoidCallback? onSubmit;
  final bool submitEnabled;
  final bool autofocus;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<InlineSearchAppBar> createState() => _InlineSearchAppBarState();
}

class _InlineSearchAppBarState extends State<InlineSearchAppBar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;
    final foreground =
        appBarTheme.foregroundColor ??
        appBarTheme.titleTextStyle?.color ??
        theme.colorScheme.onSurface;
    final titleStyle =
        (appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge)?.copyWith(
          color: foreground,
        );

    return AppBar(
      automaticallyImplyLeading: false,
      leading: BackButton(key: widget.backButtonKey, onPressed: _handleBack),
      titleSpacing: 0,
      title: TextField(
        key: widget.fieldKey,
        controller: widget.controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        maxLines: 1,
        textInputAction: TextInputAction.search,
        style: titleStyle,
        cursorColor: foreground,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          fillColor: Colors.transparent,
          hintText: widget.hintText,
          hintStyle: titleStyle?.copyWith(
            color: foreground.withValues(alpha: 0.68),
          ),
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        ),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
      actions: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            final hasQuery = value.text.trim().isNotEmpty;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value.text.isNotEmpty)
                  IconButton(
                    key: widget.clearButtonKey,
                    tooltip: widget.clearTooltip,
                    onPressed: _handleClear,
                    icon: const Icon(Icons.close),
                  ),
                if (widget.onSubmit != null)
                  IconButton(
                    key: widget.submitButtonKey,
                    tooltip: widget.submitTooltip,
                    onPressed: widget.submitEnabled && hasQuery
                        ? widget.onSubmit
                        : null,
                    icon: const Icon(Icons.search),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _handleBack() {
    widget.focusNode.unfocus();
    widget.onBack();
  }

  void _handleClear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onCleared?.call();
    widget.focusNode.requestFocus();
  }
}
