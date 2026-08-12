import 'package:flutter/material.dart';

/// Neutral cover surface used while an image is unavailable or still loading.
///
/// Keeping this intentionally free of icons avoids presenting a transient
/// decode/download state as a broken user asset.
class LibraryCoverPlaceholder extends StatelessWidget {
  const LibraryCoverPlaceholder({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: color, child: const SizedBox.expand());
  }
}
