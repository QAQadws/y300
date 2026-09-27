import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/shared/widgets/native_page_dropdown_button.dart';

/// Shared page navigation for native lists and detail surfaces.
class NativePaginationBar extends StatelessWidget {
  const NativePaginationBar({
    super.key,
    required this.currentPage,
    required this.lastPage,
    required this.hasMore,
    required this.canLoadPrevious,
    required this.isLoading,
    required this.onLoadPrevious,
    required this.onLoadNext,
    required this.onSelectPage,
    required this.previousLabel,
    required this.currentLabel,
    required this.nextLabel,
    required this.previousButtonKey,
    required this.currentPageButtonKey,
    required this.nextButtonKey,
    required this.menuKeyPrefix,
    this.padding = EdgeInsets.zero,
    this.spacing = 8,
  });

  final int currentPage;
  final int? lastPage;
  final bool hasMore;
  final bool canLoadPrevious;
  final bool isLoading;
  final VoidCallback onLoadPrevious;
  final VoidCallback onLoadNext;
  final ValueChanged<int> onSelectPage;
  final String previousLabel;
  final String currentLabel;
  final String nextLabel;
  final Key previousButtonKey;
  final Key currentPageButtonKey;
  final Key nextButtonKey;
  final String menuKeyPrefix;
  final EdgeInsetsGeometry padding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = _pageButtonStyle(Theme.of(context));
    return Padding(
      padding: padding,
      child: Center(
        heightFactor: 1,
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              key: previousButtonKey,
              height: 34,
              child: TextButton(
                onPressed: canLoadPrevious && !isLoading
                    ? onLoadPrevious
                    : null,
                style: buttonStyle,
                child: Text(previousLabel),
              ),
            ),
            NativePageDropdownButton(
              buttonKey: currentPageButtonKey,
              menuKeyPrefix: menuKeyPrefix,
              currentPage: currentPage,
              lastPage: lastPage,
              hasMore: hasMore,
              enabled: !isLoading,
              label: currentLabel,
              style: buttonStyle,
              onSelected: onSelectPage,
            ),
            if (isLoading)
              const SizedBox(
                width: 72,
                height: 34,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              SizedBox(
                key: nextButtonKey,
                height: 34,
                child: TextButton(
                  onPressed: hasMore ? onLoadNext : null,
                  style: buttonStyle,
                  child: Text(nextLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Keep the forum list's palette here so every pagination surface resolves the
// same enabled, disabled and background colors for the active theme.
ButtonStyle _pageButtonStyle(ThemeData theme) {
  final scheme = theme.colorScheme;
  final native = theme.y300NativeContent;
  final isDark = theme.brightness == Brightness.dark;
  final background =
      (isDark
              ? scheme.surfaceContainerHighest
              : Color.lerp(scheme.secondaryContainer, native.card, 0.58)!)
          .withValues(alpha: 0.42);
  return TextButton.styleFrom(
    backgroundColor: background,
    disabledBackgroundColor: background,
    foregroundColor: isDark ? scheme.primary : native.accent,
    disabledForegroundColor: isDark
        ? scheme.onSurfaceVariant.withValues(alpha: 0.44)
        : native.disabled,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
    ),
  );
}
