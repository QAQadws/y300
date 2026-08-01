import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:y300/features/thread/domain/models/post_edit_diagnostic_models.dart';

final class DefaultPostEditContractDiagnosticRecorder
    implements PostEditContractDiagnosticRecorder {
  DefaultPostEditContractDiagnosticRecorder({
    required void Function(String message) writeLog,
    bool enabled = kDebugMode,
  }) : _writeLog = writeLog,
       _enabled = enabled;

  final void Function(String message) _writeLog;
  final bool _enabled;

  @override
  void record(PostEditContractDiagnosticEvent event) {
    if (!_enabled) {
      return;
    }
    try {
      _writeLog('[PostEditContract] ${event.toSafeLogFields()}');
    } catch (_) {
      // Diagnostics must never change the edit result or state machine.
    }
  }
}

String postEditControlNameDigest(Iterable<String> names) {
  final normalized = names
      .map((name) => name.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .join('\u001f');
  return sha256.convert(utf8.encode(normalized)).toString();
}
