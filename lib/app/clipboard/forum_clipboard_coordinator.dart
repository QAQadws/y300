import 'dart:async';

import 'package:y300/core/clipboard/self_copy_fingerprint_registry.dart';

import 'forum_clipboard_link_policy.dart';

/// Owns at most one platform read and one deferred check. The host decides
/// foreground/focus/route availability and never puts those UI objects here.
final class ForumClipboardCoordinator {
  ForumClipboardCoordinator({
    required Future<String?> Function() readText,
    ForumClipboardLinkPolicy policy = const ForumClipboardLinkPolicy(),
    required SelfCopyFingerprintRegistry selfCopyRegistry,
    required void Function(ForumClipboardLinkCandidate?) onChanged,
    this.historyCapacity = 20,
  }) : _readText = readText,
       _policy = policy,
       _selfCopyRegistry = selfCopyRegistry,
       _onChanged = onChanged {
    if (historyCapacity <= 0) {
      throw ArgumentError.value(
        historyCapacity,
        'historyCapacity',
        'Must be positive',
      );
    }
  }

  final Future<String?> Function() _readText;
  final ForumClipboardLinkPolicy _policy;
  final SelfCopyFingerprintRegistry _selfCopyRegistry;
  final void Function(ForumClipboardLinkCandidate?) _onChanged;
  final int historyCapacity;
  final Set<String> _handled = {};
  ForumClipboardLinkCandidate? _candidate;
  Object? _owner;
  bool _ownerInitialized = false;
  bool _enabled = false;
  bool _available = false;
  bool _pending = false;
  bool _reading = false;
  bool _disposed = false;
  int _readGeneration = 0;
  int _operationGeneration = 0;

  ForumClipboardLinkCandidate? get candidate => _candidate;
  bool get isReading => _reading;

  void updateEligibility({
    required bool available,
    required bool enabled,
    required Object? owner,
  }) {
    if (_disposed) return;
    final ownerChanged = _ownerInitialized && owner != _owner;
    final disabled = _enabled && !enabled;
    final becameUnavailable = _available && !available;
    final hadWork = _pending || _reading || _candidate != null;
    _ownerInitialized = true;
    _owner = owner;
    _enabled = enabled;
    _available = available;
    if (ownerChanged || disabled || becameUnavailable) {
      _readGeneration++;
      if (ownerChanged || disabled) cancelOperations();
      _pending = enabled && hadWork;
      _setCandidate(null);
    }
    if (!enabled) _pending = false;
    _drain();
  }

  void requestCheck() {
    if (_disposed || !_enabled) return;
    _readGeneration++;
    cancelOperations();
    _pending = true;
    _setCandidate(null);
    _drain();
  }

  /// Real background/focus/auth changes retire navigation work. A route push
  /// only changes eligibility and deliberately does not call this method.
  void cancelOperations() {
    if (!_disposed) _operationGeneration++;
  }

  void markShown(ForumClipboardLinkCandidate candidate) {
    if (_isCurrent(candidate)) _remember(candidate.fingerprint);
  }

  void dismiss(ForumClipboardLinkCandidate candidate) {
    if (!_isCurrent(candidate)) return;
    _remember(candidate.fingerprint);
    _readGeneration++;
    cancelOperations();
    _pending = false;
    _setCandidate(null);
  }

  bool Function()? takeForOpen(ForumClipboardLinkCandidate candidate) {
    if (!_isCurrent(candidate)) return null;
    _remember(candidate.fingerprint);
    _readGeneration++;
    final generation = ++_operationGeneration;
    final owner = _owner;
    _pending = false;
    _setCandidate(null);
    // Availability can become false because this operation pushed its route.
    // The host separately cancels actual background and focus transitions.
    return () =>
        !_disposed &&
        _enabled &&
        generation == _operationGeneration &&
        owner == _owner;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _readGeneration++;
    _operationGeneration++;
    _pending = false;
    _candidate = null;
  }

  bool _isCurrent(ForumClipboardLinkCandidate candidate) =>
      !_disposed && _enabled && _available && identical(candidate, _candidate);

  void _setCandidate(ForumClipboardLinkCandidate? candidate) {
    if (identical(_candidate, candidate)) return;
    _candidate = candidate;
    _onChanged(candidate);
  }

  void _remember(String fingerprint) {
    _handled
      ..remove(fingerprint)
      ..add(fingerprint);
    if (_handled.length > historyCapacity) _handled.remove(_handled.first);
  }

  void _drain() {
    if (_disposed || !_enabled || !_available || !_pending || _reading) return;
    _pending = false;
    _reading = true;
    unawaited(_read(_readGeneration));
  }

  Future<void> _read(int generation) async {
    bool current() =>
        !_disposed && _enabled && _available && generation == _readGeneration;
    try {
      final text = await _readText();
      if (!current() || text == null) return;
      final candidate = _policy.resolve(text);
      // The bounded policy rejects oversized/nonmatching input before hashing
      // successful-write evidence for it.
      if (!current() ||
          candidate == null ||
          _selfCopyRegistry.containsText(text)) {
        return;
      }
      if (_handled.contains(candidate.fingerprint)) {
        _remember(candidate.fingerprint);
        return;
      }
      _setCandidate(candidate);
    } on Object {
      // Clipboard permissions, focus or plugin failures end this opportunity
      // quietly. A later user lifecycle opportunity can request a fresh read.
    } finally {
      _reading = false;
      _drain();
    }
  }
}
