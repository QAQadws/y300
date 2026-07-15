import 'package:flutter/material.dart';

/// Shows short-lived user feedback without adding a persistent layout region.
void showTransientSnackBar(BuildContext context, String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(trimmed)));
}
