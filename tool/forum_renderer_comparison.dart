import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/l10n/app_localizations.dart';

import 'legacy/content_rendering.dart';
import 'legacy/content_rendering/forum_html_renderer_prototype_page.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [legacyComparisonBodyOverride],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ForumHtmlRendererPrototypePage(),
      ),
    ),
  );
}
