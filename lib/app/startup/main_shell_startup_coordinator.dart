import 'dart:async';

typedef MainShellLifecycleTask =
    Future<void> Function(bool Function() isActive);

/// Owns one shell's startup attempt without taking ownership of process services.
final class MainShellStartupCoordinator {
  MainShellStartupCoordinator({
    required MainShellLifecycleTask prepareLibrary,
    required MainShellLifecycleTask initializeNotifications,
    required List<Future<void> Function()> warmups,
    bool Function()? isOwnerActive,
  }) : _prepareLibrary = prepareLibrary,
       _initializeNotifications = initializeNotifications,
       _warmups = List.unmodifiable(warmups),
       _isOwnerActive = isOwnerActive;

  final MainShellLifecycleTask _prepareLibrary;
  final MainShellLifecycleTask _initializeNotifications;
  final List<Future<void> Function()> _warmups;
  final bool Function()? _isOwnerActive;
  Future<void>? _ready;
  bool _disposed = false;

  bool get isActive => !_disposed && (_isOwnerActive?.call() ?? true);

  Future<void> start() {
    final ready = _ready;
    if (ready != null) return ready;
    if (!isActive) return Future<void>.value();
    final operation = _runSafely(() => _prepareLibrary(() => isActive));
    _ready = operation;
    unawaited(_runSafely(() => _initializeNotifications(() => isActive)));
    for (final warmup in _warmups) {
      unawaited(_runSafely(warmup));
    }
    return operation;
  }

  Future<void> _runSafely(Future<void> Function() task) async {
    if (!isActive) return;
    await _runStartupTaskSafely(task);
  }

  void dispose() => _disposed = true;
}

/// Finish interrupted cover merges before shelves render. Cache maintenance
/// and download recovery run independently of shelf readiness.
Future<void> runMainShellBackgroundTasks({
  required bool Function() isActive,
  Future<void> Function()? recoverCoverMerges,
  required List<Future<void> Function()> maintenance,
}) async {
  if (!isActive()) return;
  if (recoverCoverMerges != null) {
    await _runStartupTaskSafely(recoverCoverMerges);
  }
  for (final task in maintenance) {
    if (!isActive()) return;
    unawaited(_runStartupTaskSafely(task));
  }
}

Future<void> _runStartupTaskSafely(Future<void> Function() task) async {
  try {
    await task();
  } catch (_) {
    // Independent startup work must not make the main shell unusable.
  }
}
