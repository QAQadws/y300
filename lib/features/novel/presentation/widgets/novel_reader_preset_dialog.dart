import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/features/fonts/fonts.dart' show FontIdentity;
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_preferences.dart';
import '../../domain/repositories/novel_reader_preset_repository.dart';

enum _PresetAction { rename, reset }

class NovelReaderPresetDialog extends StatefulWidget {
  const NovelReaderPresetDialog({
    super.key,
    required this.repository,
    required this.current,
    required this.fontAvailable,
  });

  final NovelReaderPresetRepository repository;
  final NovelReaderPreferences current;
  final Future<bool> Function(String) fontAvailable;

  @override
  State<NovelReaderPresetDialog> createState() =>
      _NovelReaderPresetDialogState();
}

class _NovelReaderPresetDialogState extends State<NovelReaderPresetDialog> {
  List<NovelReaderPreset>? _presets;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_update(widget.repository.load));
  }

  Future<void> _update(
    Future<List<NovelReaderPreset>> Function() action,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final values = await action();
      if (mounted) setState(() => _presets = values);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final presets = _presets;
    return AlertDialog(
      key: const Key('novel-reader-presets-dialog'),
      scrollable: true,
      title: Text(l10n.novelReaderPresets),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_failed)
              Text(
                presets == null
                    ? l10n.novelReaderPresetLoadFailed
                    : l10n.novelReaderPresetSaveFailed,
              ),
            if (_failed && presets == null)
              TextButton(
                onPressed: _busy ? null : () => _update(widget.repository.load),
                child: Text(l10n.commonRetry),
              ),
            if (presets?.isEmpty == true) Text(l10n.novelReaderPresetsEmpty),
            if (presets != null)
              for (final preset in presets)
                ListTile(
                  key: ValueKey('novel-reader-preset-${preset.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(preset.name),
                  subtitle: Text(
                    preset.preferences == null
                        ? l10n.novelReaderPresetUnavailable
                        : l10n.novelReaderPresetApplyHint,
                  ),
                  onTap: _busy || preset.preferences == null
                      ? null
                      : () => _apply(preset.preferences!),
                  trailing: PopupMenuButton<_PresetAction>(
                    key: ValueKey('novel-reader-preset-actions-${preset.id}'),
                    tooltip: l10n.novelReaderPresetActions,
                    enabled: !_busy,
                    onSelected: (action) {
                      switch (action) {
                        case _PresetAction.rename:
                          _editName(preset);
                        case _PresetAction.reset:
                          _reset(preset);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _PresetAction.rename,
                        child: Text(l10n.novelReaderRenamePreset),
                      ),
                      PopupMenuItem(
                        value: _PresetAction.reset,
                        enabled: preset.preferences != null,
                        child: Text(l10n.novelReaderResetPreset),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('novel-reader-save-preset'),
          onPressed: _busy || presets == null ? null : () => _editName(),
          child: Text(l10n.novelReaderSavePreset),
        ),
      ],
    );
  }

  Future<void> _editName([NovelReaderPreset? preset]) async {
    final l10n = AppLocalizations.of(context);
    var name = preset?.name ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            if (NovelReaderPreset.isValidName(name)) {
              Navigator.of(context).pop(name.trim());
            }
          }

          return AlertDialog(
            title: Text(
              preset == null
                  ? l10n.novelReaderSavePreset
                  : l10n.novelReaderRenamePreset,
            ),
            content: TextFormField(
              key: const Key('novel-reader-preset-name'),
              autofocus: true,
              maxLength: NovelReaderPreset.maxNameLength,
              initialValue: name,
              decoration: InputDecoration(
                labelText: l10n.novelReaderPresetName,
              ),
              onChanged: (value) => setDialogState(() => name = value),
              onFieldSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              TextButton(
                key: const Key('novel-reader-confirm-preset-name'),
                onPressed: NovelReaderPreset.isValidName(name) ? submit : null,
                child: Text(l10n.commonSave),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || result == null) return;
    await _update(
      () => preset == null
          ? widget.repository.save(result, widget.current)
          : widget.repository.rename(preset.id, result),
    );
  }

  Future<void> _reset(NovelReaderPreset preset) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(
      title: l10n.novelReaderResetPreset,
      message: l10n.novelReaderResetPresetBody,
      action: l10n.commonReset,
      key: const Key('novel-reader-confirm-reset-preset'),
    );
    if (!mounted || !confirmed) return;
    await _update(() => widget.repository.reset(preset.id));
  }

  Future<void> _apply(NovelReaderPreferences preferences) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var available = preferences.fontFamily == FontIdentity.system;
      if (!available) {
        try {
          available = await widget.fontAvailable(preferences.fontFamily);
        } catch (_) {
          available = false;
        }
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (!available) {
        setState(() => _busy = false);
        final l10n = AppLocalizations.of(context);
        final confirmed = await _confirm(
          title: l10n.novelReaderPresetFontUnavailable,
          message: l10n.novelReaderPresetFontUnavailableBody,
          action: l10n.commonApply,
          key: const Key('novel-reader-apply-preset-with-current-font'),
        );
        if (!mounted || !confirmed) return;
      }
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context)
            .pop((preferences: preferences, keepCurrentFont: !available));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    required Key key,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            TextButton(
              key: key,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}
