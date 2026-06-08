import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_progress_control.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_tool_button.dart';

class ReaderBottomOverlayPanel extends StatelessWidget {
  const ReaderBottomOverlayPanel({
    super.key,
    required this.config,
  });

  final ReaderBottomBarConfig config;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('shared-reader-bottom-overlay-panel'),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (config.showProgress) ReaderProgressControl(config: config.progress),
              if (config.actions.isNotEmpty) ...[
                if (config.showProgress) const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final action in config.actions)
                      ReaderToolButton(
                        key: Key('shared-reader-bottom-action-${action.id}'),
                        icon: action.icon,
                        label: action.label,
                        enabled: action.enabled,
                        onPressed: action.onPressed,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
