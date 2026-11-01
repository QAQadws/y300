import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';
import 'novel_reader_style_scope_settings_panel.dart';

class NovelReaderFontSizePolicySettingsPanel extends StatelessWidget {
  const NovelReaderFontSizePolicySettingsPanel({
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
    return NovelReaderStyleScopeSettingsPanel(
      keyPrefix: 'novel-reader-font-size',
      value: value.fontSizeScope,
      enabled: enabled,
      labels: (
        title: l10n.novelFontSizePolicy,
        original: l10n.novelFontSizePolicyOriginal,
        author: l10n.novelFontSizePolicyAuthor,
        body: l10n.novelFontSizePolicyBody,
        all: l10n.novelFontSizePolicyAll,
        hint: l10n.novelFontSizePolicyHint,
        allHint: l10n.novelFontSizePolicyAllHint,
        unavailable: l10n.novelFontSizePolicyUnavailable,
        reset: l10n.novelFontSizePolicyReset,
      ),
      onChanged: (scope) => onChanged(value.withFontSizeScope(scope)),
    );
  }
}
