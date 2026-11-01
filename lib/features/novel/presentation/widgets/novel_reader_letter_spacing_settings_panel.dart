import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';
import 'novel_reader_scoped_number_settings_panel.dart';

class NovelReaderLetterSpacingSettingsPanel extends StatelessWidget {
  const NovelReaderLetterSpacingSettingsPanel({
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
    final stored = value.letterSpacing;
    final request = stored?.isValid == true ? stored : null;
    return NovelReaderScopedNumberSettingsPanel(
      keyPrefix: 'novel-reader-letter-spacing',
      value: request == null
          ? null
          : (number: request.logicalPixels, scope: request.scope),
      canReset: stored != null,
      minimum: NovelReaderLetterSpacing.minimum,
      maximum: NovelReaderLetterSpacing.maximum,
      step: NovelReaderLetterSpacing.step,
      enabled: enabled,
      labels: (
        scope: l10n.novelLetterSpacingScope,
        original: l10n.novelLetterSpacingOriginal,
        missing: l10n.novelLetterSpacingMissing,
        body: l10n.novelLetterSpacingBody,
        all: l10n.novelLetterSpacingAll,
        amount: l10n.novelLetterSpacingAmount,
        hint: l10n.novelLetterSpacingHint,
        unavailable: l10n.novelLetterSpacingUnavailable,
        reset: l10n.novelLetterSpacingReset,
        formatNumber: l10n.novelLetterSpacingValue,
      ),
      onChanged: (next) => onChanged(
        value.withLetterSpacing(
          next == null
              ? null
              : NovelReaderLetterSpacing(
                  logicalPixels: next.number,
                  scope: next.scope,
                ),
        ),
      ),
    );
  }
}
