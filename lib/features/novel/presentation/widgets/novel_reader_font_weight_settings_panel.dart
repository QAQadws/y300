import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';
import 'novel_reader_scoped_number_settings_panel.dart';

class NovelReaderFontWeightSettingsPanel extends StatelessWidget {
  const NovelReaderFontWeightSettingsPanel({
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
    final stored = value.fontWeight;
    final request = stored?.isValid == true ? stored : null;
    return NovelReaderScopedNumberSettingsPanel(
      keyPrefix: 'novel-reader-font-weight',
      value: request == null
          ? null
          : (number: request.value.toDouble(), scope: request.scope),
      canReset: stored != null,
      minimum: NovelReaderFontWeight.minimum.toDouble(),
      maximum: NovelReaderFontWeight.maximum.toDouble(),
      step: NovelReaderFontWeight.step.toDouble(),
      initialNumber: NovelReaderFontWeight.initial.toDouble(),
      fractionDigits: 0,
      enabled: enabled,
      labels: (
        scope: l10n.novelFontWeightScope,
        original: l10n.novelFontWeightOriginal,
        missing: l10n.novelFontWeightMissing,
        body: l10n.novelFontWeightBody,
        all: l10n.novelFontWeightAll,
        amount: l10n.novelFontWeightAmount,
        hint: l10n.novelFontWeightHint,
        unavailable: l10n.novelFontWeightUnavailable,
        reset: l10n.novelFontWeightReset,
        formatNumber: l10n.novelFontWeightValue,
      ),
      onChanged: (next) => onChanged(
        value.withFontWeight(
          next == null
              ? null
              : NovelReaderFontWeight(
                  value: next.number.toInt(),
                  scope: next.scope,
                ),
        ),
      ),
    );
  }
}
