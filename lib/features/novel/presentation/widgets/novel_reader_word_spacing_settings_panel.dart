import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';
import 'novel_reader_scoped_number_settings_panel.dart';

class NovelReaderWordSpacingSettingsPanel extends StatelessWidget {
  const NovelReaderWordSpacingSettingsPanel({
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
    final stored = value.wordSpacing;
    final request = stored?.isValid == true ? stored : null;
    return NovelReaderScopedNumberSettingsPanel(
      keyPrefix: 'novel-reader-word-spacing',
      value: request == null
          ? null
          : (number: request.logicalPixels, scope: request.scope),
      canReset: stored != null,
      minimum: NovelReaderWordSpacing.minimum,
      maximum: NovelReaderWordSpacing.maximum,
      step: NovelReaderWordSpacing.step,
      enabled: enabled,
      labels: (
        scope: l10n.novelWordSpacingScope,
        original: l10n.novelWordSpacingOriginal,
        missing: l10n.novelWordSpacingMissing,
        body: l10n.novelWordSpacingBody,
        all: l10n.novelWordSpacingAll,
        amount: l10n.novelWordSpacingAmount,
        hint: l10n.novelWordSpacingHint,
        unavailable: l10n.novelWordSpacingUnavailable,
        reset: l10n.novelWordSpacingReset,
        formatNumber: l10n.novelWordSpacingValue,
      ),
      onChanged: (next) => onChanged(
        value.withWordSpacing(
          next == null
              ? null
              : NovelReaderWordSpacing(
                  logicalPixels: next.number,
                  scope: next.scope,
                ),
        ),
      ),
    );
  }
}
