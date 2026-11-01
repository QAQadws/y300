import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_preferences.dart';
import '../services/novel_reader_color_contrast.dart';
import '../services/novel_reader_display_resolvers.dart';

/// Presentation only; the existing display-preference coordinator owns saves.
class NovelReaderColorSettingsPanel extends StatelessWidget {
  const NovelReaderColorSettingsPanel({
    super.key,
    required this.preferences,
    required this.enabled,
    required this.onChanged,
  });
  final NovelReaderPreferences preferences;
  final bool enabled;
  final ValueChanged<NovelReaderColorOverrides> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: preferences,
      theme: Theme.of(context),
    );
    final colors = preferences.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ColorSetting(
          keyPrefix: 'novel-reader-foreground',
          title: l10n.novelColorForeground,
          resetLabel: l10n.novelColorForegroundReset,
          value: colors.foreground,
          inherited: palette.foreground,
          enabled: enabled,
          onChanged: (next) => onChanged(colors.withForeground(next)),
        ),
        _ColorSetting(
          keyPrefix: 'novel-reader-background',
          title: l10n.novelColorBackground,
          resetLabel: l10n.novelColorBackgroundReset,
          value: colors.background,
          inherited: palette.background,
          enabled: enabled,
          onChanged: (next) => onChanged(colors.withBackground(next)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(
            !enabled
                ? l10n.novelColorUnavailable
                : novelReaderColorContrast(
                        palette.foreground,
                        palette.background,
                      ) <
                      4.5
                ? l10n.novelColorLowContrast
                : l10n.novelColorHint,
            key: const Key('novel-reader-color-hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

String _hex(int value) =>
    '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';

class _ColorSetting extends StatefulWidget {
  const _ColorSetting({
    required this.keyPrefix,
    required this.title,
    required this.resetLabel,
    required this.value,
    required this.inherited,
    required this.enabled,
    required this.onChanged,
  });
  final String keyPrefix, title, resetLabel;
  final int? value;
  final Color inherited;
  final bool enabled;
  final ValueChanged<int?> onChanged;
  @override
  State<_ColorSetting> createState() => _ColorSettingState();
}

class _ColorSettingState extends State<_ColorSetting> {
  bool _editing = false;
  Future<void> _edit() async {
    setState(() => _editing = true);
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _ColorDialog(
        title: widget.title,
        initial: widget.value ?? (widget.inherited.toARGB32() & 0xffffff),
      ),
    );
    if (!mounted) return;
    setState(() => _editing = false);
    // Use the current callback/enablement after the asynchronous dialog.
    if (result != null && widget.enabled) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 12, 0),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: Key('${widget.keyPrefix}-edit'),
            onPressed: widget.enabled && !_editing ? _edit : null,
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: widget.value == null
                          ? widget.inherited
                          : Color(0xff000000 | widget.value!),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.title)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.value == null
                        ? AppLocalizations.of(context).novelColorInherited
                        : _hex(widget.value!),
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          key: Key('${widget.keyPrefix}-reset'),
          tooltip: widget.resetLabel,
          onPressed: widget.value == null || _editing
              ? null
              : () => widget.onChanged(null),
          icon: const Icon(Icons.restart_alt),
        ),
      ],
    ),
  );
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.title, required this.initial});
  final String title;
  final int initial;
  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late final _controller = TextEditingController(text: _hex(widget.initial));
  int? get _rgb {
    final text = _controller.text.trim();
    if (!RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(text)) return null;
    return int.parse(text.replaceFirst('#', ''), radix: 16);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('novel-reader-color-input'),
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: l10n.novelColorHex,
          helperText: l10n.novelColorHexHint,
          errorText: _rgb == null ? l10n.novelColorHexInvalid : null,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_rgb case final rgb?) Navigator.pop(context, rgb);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('novel-reader-color-apply'),
          onPressed: _rgb == null ? null : () => Navigator.pop(context, _rgb),
          child: Text(l10n.commonApply),
        ),
      ],
    );
  }
}
