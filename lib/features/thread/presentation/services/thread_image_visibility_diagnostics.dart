import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// Page-owned diagnostics. Release can opt in with Y300_RENDER_METRICS; no
/// content, URL or filesystem identity crosses the numeric snapshot boundary.
final class ThreadImageVisibilityDiagnostics
    implements ForumHtmlImageVisibilityObserver {
  ThreadImageVisibilityDiagnostics({
    bool enabled =
        kDebugMode || const bool.fromEnvironment('Y300_RENDER_METRICS'),
    void Function(String)? writeLog,
  }) : _enabled = enabled,
       _writeLog = writeLog ?? debugPrint,
       _metrics = enabled ? ForumHtmlImageVisibilityMetrics() : null;

  final bool _enabled;
  final void Function(String) _writeLog;
  ForumHtmlImageVisibilityMetrics? _metrics;
  bool _disposed = false;

  ForumHtmlImageVisibilityObserver? get observer =>
      _metrics == null ? null : this;

  @override
  void observe(
    Object identity, {
    required bool visible,
    required bool painted,
    required bool failed,
  }) => _metrics?.observe(
    identity,
    visible: visible,
    painted: painted,
    failed: failed,
  );

  @override
  void retire(Object identity) => _metrics?.retire(identity);

  void checkpoint(String reason) {
    final snapshot = _metrics?.snapshot;
    if (snapshot == null || snapshot.values['entries'] == 0) return;
    try {
      _writeLog(
        '[ThreadImageVisibility] ${jsonEncode({'reason': reason, ...snapshot.toJson()})}',
      );
    } catch (_) {
      // A diagnostic sink cannot change page navigation or cleanup.
    }
  }

  void reset() {
    if (_disposed) return;
    _metrics?.close();
    checkpoint('source_changed');
    _metrics = _enabled ? ForumHtmlImageVisibilityMetrics() : null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _metrics?.close();
    checkpoint('disposed');
    _metrics = null;
  }
}
