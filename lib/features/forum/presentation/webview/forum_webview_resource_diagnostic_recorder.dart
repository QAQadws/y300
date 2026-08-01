import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/domain/models/forum_webview_resource_diagnostic_models.dart';

final forumWebViewResourceDiagnosticRecorderProvider =
    Provider<ForumWebViewResourceDiagnosticRecorder>((ref) {
      final logger = ref.watch(loggerProvider);
      return DefaultForumWebViewResourceDiagnosticRecorder(writeLog: logger.w);
    });

abstract class ForumWebViewResourceDiagnosticRecorder {
  void record(ForumWebViewResourceDiagnosticEvent event);
}

class DefaultForumWebViewResourceDiagnosticRecorder
    implements ForumWebViewResourceDiagnosticRecorder {
  DefaultForumWebViewResourceDiagnosticRecorder({
    required void Function(String message) writeLog,
    bool isDebugMode = kDebugMode,
  }) : _writeLog = writeLog,
       _isDebugMode = isDebugMode;

  final void Function(String message) _writeLog;
  final bool _isDebugMode;

  @override
  void record(ForumWebViewResourceDiagnosticEvent event) {
    if (!_isDebugMode || !_shouldRecord(event)) {
      return;
    }
    _writeLog(_formatEvent(event));
  }

  bool _shouldRecord(ForumWebViewResourceDiagnosticEvent event) {
    if (event.kind == ForumWebViewResourceKind.other) {
      return false;
    }
    final statusCode = event.statusCode;
    if (statusCode != null && statusCode >= 400) {
      return true;
    }
    final errorDescription = event.errorDescription?.trim();
    return errorDescription != null && errorDescription.isNotEmpty;
  }

  String _formatEvent(ForumWebViewResourceDiagnosticEvent event) {
    final statusCode = event.statusCode?.toString() ?? '-';
    final errorDescription = event.errorDescription?.trim();
    final errorValue = (errorDescription == null || errorDescription.isEmpty)
        ? '-'
        : errorDescription;
    return '[ForumWebView][resource][${event.kind.name}] '
        'mainFrame=${event.isMainFrame} status=$statusCode '
        'uri=${event.uri} error=$errorValue';
  }
}
