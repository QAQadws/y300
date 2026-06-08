import 'package:flutter/material.dart';

class ReaderToolButton extends StatelessWidget {
  const ReaderToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: label,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
    );
  }
}
