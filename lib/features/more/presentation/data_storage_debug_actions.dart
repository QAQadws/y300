import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

List<Widget> buildDataStorageDebugActionWidgets({
  required bool enabled,
  required AppLocalizations l10n,
  required VoidCallback onReloadUsage,
  required VoidCallback onExportDiagnostics,
}) {
  if (!kDebugMode) {
    return const <Widget>[];
  }
  return <Widget>[
    Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('data-storage-reload-usage-button'),
            onPressed: enabled ? onReloadUsage : null,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.moreStorageReloadUsage),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('data-storage-export-diagnostics-button'),
            onPressed: enabled ? onExportDiagnostics : null,
            icon: const Icon(Icons.file_download_outlined),
            label: Text(l10n.moreStorageExportDiagnostics),
          ),
        ),
      ],
    ),
    const Divider(height: 32),
  ];
}
