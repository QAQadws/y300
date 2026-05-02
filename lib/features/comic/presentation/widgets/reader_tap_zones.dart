import 'package:flutter/material.dart';

/// Reader tap-zone layout used by phase-2 menu interaction.
///
/// The center zone toggles reader UI visibility.
/// Left/right callbacks are optional and reserved for paged mode behavior.
class ReaderTapZones extends StatelessWidget {
  const ReaderTapZones({
    super.key,
    required this.onCenterTap,
    this.onLeftTap,
    this.onRightTap,
    this.enabled = true,
  });

  final VoidCallback onCenterTap;
  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              key: const Key('comic-reader-left-tap-zone'),
              behavior: HitTestBehavior.translucent,
              onTap: enabled ? onLeftTap : null,
              child: const SizedBox.expand(),
            ),
          ),
          Expanded(
            child: GestureDetector(
              key: const Key('comic-reader-center-tap-zone'),
              behavior: HitTestBehavior.translucent,
              onTap: enabled ? onCenterTap : null,
              child: const SizedBox.expand(),
            ),
          ),
          Expanded(
            child: GestureDetector(
              key: const Key('comic-reader-right-tap-zone'),
              behavior: HitTestBehavior.translucent,
              onTap: enabled ? onRightTap : null,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}
