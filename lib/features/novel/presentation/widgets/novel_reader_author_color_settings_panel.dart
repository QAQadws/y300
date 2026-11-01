import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../domain/models/novel_reader_preferences.dart';
import 'novel_reader_style_scope_settings_panel.dart';

/// Foreground overrides and author highlights are independent of canvas paint.
class NovelReaderAuthorColorSettingsPanel extends StatelessWidget {
  const NovelReaderAuthorColorSettingsPanel({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final NovelReaderColorOverrides value;
  final bool enabled;
  final ValueChanged<NovelReaderColorOverrides> onChanged;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        NovelReaderStyleScopeSettingsPanel(
          keyPrefix: 'novel-reader-author-foreground',
          value: value.foregroundScope,
          enabled: enabled,
          onChanged: (next) => onChanged(value.withForegroundScope(next)),
          labels: (
            title: l10n.novelAuthorForeground,
            original: l10n.novelAuthorColorOriginal,
            author: l10n.novelAuthorColorPreserve,
            body: l10n.novelAuthorForegroundBody,
            all: l10n.novelAuthorForegroundAll,
            hint: l10n.novelAuthorForegroundHint,
            allHint: l10n.novelAuthorForegroundAllHint,
            unavailable: l10n.novelAuthorColorUnavailable,
            reset: l10n.novelAuthorForegroundReset,
          ),
        ),
        NovelReaderStyleScopeSettingsPanel(
          keyPrefix: 'novel-reader-author-background',
          value: value.backgroundScope,
          enabled: enabled,
          onChanged: (next) => onChanged(value.withBackgroundScope(next)),
          labels: (
            title: l10n.novelAuthorBackground,
            original: l10n.novelAuthorColorOriginal,
            author: l10n.novelAuthorColorPreserve,
            body: l10n.novelAuthorBackgroundBody,
            all: l10n.novelAuthorBackgroundAll,
            hint: l10n.novelAuthorBackgroundHint,
            allHint: l10n.novelAuthorBackgroundAllHint,
            unavailable: l10n.novelAuthorColorUnavailable,
            reset: l10n.novelAuthorBackgroundReset,
          ),
        ),
      ],
    );
  }
}
