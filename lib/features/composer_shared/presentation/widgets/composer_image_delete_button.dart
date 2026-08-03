import 'package:flutter/material.dart';

/// Shared delete affordance for composer image cards.
///
/// The 40dp interaction target intentionally contains a smaller 24dp visual
/// circle so dense image grids remain easy to scan without shrinking the tap
/// target below Material guidance.
class ComposerImageDeleteButton extends StatelessWidget {
  const ComposerImageDeleteButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.visualKey,
    this.isBusy = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Key? visualKey;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null && !isBusy;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: SizedBox.square(
          dimension: 40,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: enabled ? onPressed : null,
              customBorder: const CircleBorder(),
              child: Center(
                child: DecoratedBox(
                  key: visualKey,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: 24,
                    child: isBusy
                        ? const Padding(
                            padding: EdgeInsets.all(5),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.close, size: 14),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
