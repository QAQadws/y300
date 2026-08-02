import 'package:flutter/material.dart';

/// Shared underline-only decoration for title fields on composer surfaces.
InputDecoration composerTitleFieldDecoration(
  BuildContext context, {
  required String hintText,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final underlineBorder = UnderlineInputBorder(
    borderSide: BorderSide(color: colorScheme.outlineVariant),
  );
  final focusedUnderlineBorder = UnderlineInputBorder(
    borderSide: BorderSide(color: colorScheme.primary, width: 2),
  );
  final errorUnderlineBorder = UnderlineInputBorder(
    borderSide: BorderSide(color: colorScheme.error, width: 2),
  );
  return InputDecoration(
    hintText: hintText,
    filled: false,
    border: underlineBorder,
    enabledBorder: underlineBorder,
    focusedBorder: focusedUnderlineBorder,
    errorBorder: errorUnderlineBorder,
    focusedErrorBorder: errorUnderlineBorder,
    disabledBorder: underlineBorder,
  );
}
