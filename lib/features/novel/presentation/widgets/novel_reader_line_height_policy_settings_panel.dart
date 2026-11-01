import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_typography_overrides.dart';
import 'novel_reader_style_scope_settings_panel.dart';

class NovelReaderLineHeightPolicySettingsPanel extends StatelessWidget {
  const NovelReaderLineHeightPolicySettingsPanel({
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
      keyPrefix: 'novel-reader-line-height',
      value: value.lineHeightScope,
      enabled: enabled,
      labels: (
        title: l10n.novelLineHeightPolicy,
        original: l10n.novelLineHeightPolicyOriginal,
        author: l10n.novelLineHeightPolicyAuthor,
        body: l10n.novelLineHeightPolicyBody,
        all: l10n.novelLineHeightPolicyAll,
        hint: l10n.novelLineHeightPolicyHint,
        allHint: l10n.novelLineHeightPolicyAllHint,
        unavailable: l10n.novelLineHeightPolicyUnavailable,
        reset: l10n.novelLineHeightPolicyReset,
      ),
      onChanged: (scope) => onChanged(value.withLineHeightScope(scope)),
    );
  }
}
