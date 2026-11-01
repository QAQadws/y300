import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';
import 'novel_reader_style_scope_settings_panel.dart';

class NovelReaderTextAlignmentSettingsPanel extends StatelessWidget {
  const NovelReaderTextAlignmentSettingsPanel({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final NovelReaderTypographyOverrides value;
  final bool enabled;
  final ValueChanged<NovelReaderTypographyOverrides> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final request = value.textAlignment;
    return NovelReaderStyleScopeSettingsPanel(
      keyPrefix: 'novel-reader-text-alignment',
      value: request?.scope,
      enabled: enabled,
      labels: (
        title: l10n.novelTextAlignmentScope,
        original: l10n.novelTextAlignmentOriginal,
        author: l10n.novelTextAlignmentMissing,
        body: l10n.novelTextAlignmentBody,
        all: l10n.novelTextAlignmentAll,
        hint: l10n.novelTextAlignmentHint,
        allHint: l10n.novelTextAlignmentAllHint,
        unavailable: l10n.novelTextAlignmentUnavailable,
        reset: l10n.novelTextAlignmentReset,
      ),
      onChanged: (scope) => onChanged(
        value.withTextAlignment(
          scope == null
              ? null
              : NovelReaderTextAlignment(
                  mode: request?.mode ?? NovelReaderTextAlignMode.start,
                  scope: scope,
                ),
        ),
      ),
      valueControl: request == null
          ? null
          : ReaderSegmentControl<NovelReaderTextAlignMode>(
              key: const Key('novel-reader-text-alignment-mode'),
              label: l10n.novelTextAlignmentMode,
              value: request.mode,
              values: const [
                NovelReaderTextAlignMode.start,
                NovelReaderTextAlignMode.end,
                NovelReaderTextAlignMode.justify,
                NovelReaderTextAlignMode.center,
              ],
              enabled: enabled,
              labelBuilder: (mode) => switch (mode) {
                NovelReaderTextAlignMode.start => l10n.novelTextAlignmentStart,
                NovelReaderTextAlignMode.end => l10n.novelTextAlignmentEnd,
                NovelReaderTextAlignMode.justify =>
                  l10n.novelTextAlignmentJustify,
                NovelReaderTextAlignMode.center =>
                  l10n.novelTextAlignmentCenter,
              },
              onChanged: (mode) => onChanged(
                value.withTextAlignment(
                  NovelReaderTextAlignment(mode: mode, scope: request.scope),
                ),
              ),
            ),
    );
  }
}
