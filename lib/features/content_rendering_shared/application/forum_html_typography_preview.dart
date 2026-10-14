import 'dart:async';

import '../../reader_shared/domain/rich_text/typography/rich_text_typography.dart';

/// A settings gesture owns only its latest draft and two bounded timers.
final class ForumHtmlTypographyPreview {
  ForumHtmlTypographyPreview({
    required RichTextTypography initialValue,
    required void Function(RichTextTypography) preview,
    required Future<void> Function(RichTextTypography) commit,
    required void Function(Object, StackTrace) onError,
  }) : _value = initialValue,
       _lastPreview = initialValue,
       _preview = preview,
       _commit = commit,
       _onError = onError;

  final void Function(RichTextTypography) _preview;
  final Future<void> Function(RichTextTypography) _commit;
  final void Function(Object, StackTrace) _onError;
  RichTextTypography _value;
  RichTextTypography _lastPreview;
  Timer? _previewTimer;
  Timer? _saveTimer;
  bool _active = true;

  bool get isActive => _active;
  RichTextTypography get value => _value;

  void change(RichTextTypography value) {
    if (!_active || _value == value) return;
    _value = value;
    if (_previewTimer == null) {
      apply();
      _schedulePreview();
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 520), () {
      _saveTimer = null;
      _observe(flush());
    });
  }

  void _schedulePreview() {
    _previewTimer = Timer(const Duration(milliseconds: 90), () {
      _previewTimer = null;
      if (!_active || _lastPreview == _value) return;
      apply();
      // Keep the next interval closed after a trailing preview too, so a
      // continuous drag cannot publish again immediately after this tick.
      _schedulePreview();
    });
  }

  void apply() {
    if (!_active || _lastPreview == _value) return;
    _lastPreview = _value;
    _preview(_value);
  }

  Future<void> flush() {
    if (!_active) return Future<void>.value();
    _cancelTimers();
    apply();
    return _commit(_value);
  }

  /// Dismissal can occur while Flutter is disposing the sheet. Publish the
  /// final draft after that build phase, without using the sheet's Context/Ref.
  void close() {
    if (!_active) return;
    _cancelTimers();
    scheduleMicrotask(() {
      if (!_active) return;
      final future = flush();
      cancel();
      _observe(future);
    });
  }

  void cancel() {
    _active = false;
    _cancelTimers();
  }

  void _cancelTimers() {
    _previewTimer?.cancel();
    _previewTimer = null;
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  void _observe(Future<void> future) {
    unawaited(
      future.catchError((Object error, StackTrace stack) {
        _onError(error, stack);
      }),
    );
  }
}
