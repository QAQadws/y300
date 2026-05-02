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
  });

  final VoidCallback onCenterTap;
  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              key: const Key('comic-reader-left-tap-zone'),
              behavior: HitTestBehavior.translucent,
              onTap: onLeftTap,
              child: const SizedBox.expand(),
            ),
          ),
          Expanded(
            child: GestureDetector(
              key: const Key('comic-reader-center-tap-zone'),
              behavior: HitTestBehavior.translucent,
              onTap: onCenterTap,
              child: const SizedBox.expand(),
            ),
          ),
          Expanded(
            child: GestureDetector(
              key: const Key('comic-reader-right-tap-zone'),
              behavior: HitTestBehavior.translucent,
              onTap: onRightTap,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}
