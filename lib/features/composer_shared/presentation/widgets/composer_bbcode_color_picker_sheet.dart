import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:y300/l10n/app_localizations.dart';

class ComposerBbCodeColorPickerSheet extends StatefulWidget {
  const ComposerBbCodeColorPickerSheet({
    super.key,
    required this.keyPrefix,
    required this.title,
    required this.initialColor,
  });

  final String keyPrefix;
  final String title;
  final Color initialColor;

  @override
  State<ComposerBbCodeColorPickerSheet> createState() =>
      _ComposerBbCodeColorPickerSheetState();
}

class _ComposerBbCodeColorPickerSheetState
    extends State<ComposerBbCodeColorPickerSheet> {
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: Column(
          key: Key('${widget.keyPrefix}-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ColorPicker(
              key: Key('${widget.keyPrefix}-picker'),
              pickerColor: _selectedColor,
              onColorChanged: (color) {
                setState(() {
                  _selectedColor = color.withValues(alpha: 1);
                });
              },
              enableAlpha: false,
              hexInputBar: true,
              displayThumbColor: true,
              portraitOnly: true,
              labelTypes: const [],
              pickerAreaHeightPercent: 0.72,
              colorPickerWidth: width.clamp(240, 360).toDouble(),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: Key('${widget.keyPrefix}-cancel-button'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: Key('${widget.keyPrefix}-use-button'),
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pop(composerBbCodeColorToHex(_selectedColor));
                  },
                  child: Text(l10n.commonUse),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> showComposerBbCodeColorPickerSheet({
  required BuildContext context,
  required String keyPrefix,
  required String title,
  required Color initialColor,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ComposerBbCodeColorPickerSheet(
      keyPrefix: keyPrefix,
      title: title,
      initialColor: initialColor,
    ),
  );
}

String composerBbCodeColorToHex(Color color) {
  return colorToHex(
    color.withValues(alpha: 1),
    includeHashSign: true,
    enableAlpha: false,
    toUpperCase: false,
  );
}

String? normalizeComposerBbCodeHexColor(String rawColor) {
  final normalized = rawColor.trim();
  final match = RegExp(
    r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$',
  ).firstMatch(normalized);
  if (match == null) {
    return null;
  }
  final hex = match.group(1)!.toLowerCase();
  final expanded = hex.length == 3
      ? hex.split('').map((digit) => '$digit$digit').join()
      : hex;
  return '#$expanded';
}

Color? parseComposerBbCodeHexColor(String rawColor) {
  final normalized = normalizeComposerBbCodeHexColor(rawColor);
  if (normalized == null) {
    return null;
  }
  return Color(int.parse('ff${normalized.substring(1)}', radix: 16));
}

@Deprecated('Use normalizeComposerBbCodeHexColor for shared color handling.')
String? normalizeComposerBackColorHex(String rawColor) {
  return normalizeComposerBbCodeHexColor(rawColor);
}
