import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

List<Widget> buildDataStorageDebugActionWidgets({
  required bool enabled,
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
            label: const Text('重新统计'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('data-storage-export-diagnostics-button'),
            onPressed: enabled ? onExportDiagnostics : null,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('缓存诊断导出'),
          ),
        ),
      ],
    ),
    const Divider(height: 32),
  ];
}
