import 'package:flutter/foundation.dart';

/// Emits stable, low-volume diagnostics for the novel progress lifecycle.
///
/// Callers should log state boundaries rather than scroll frames so a copied
/// device log can reconstruct one open, restore, and persistence transaction.
final class NovelReaderProgressDiagnostics {
  const NovelReaderProgressDiagnostics();

  void log(String event, {Map<String, Object?> fields = const {}}) {
    final details = fields.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${_singleLine(entry.value)}')
        .join(' ');
    debugPrint(
      details.isEmpty
          ? '[NovelReaderProgress][$event]'
          : '[NovelReaderProgress][$event] $details',
    );
  }

  String _singleLine(Object? value) {
    return value.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
  }
}
