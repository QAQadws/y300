import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/profile/presentation/daily_sign_in_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

/// Bridges app lifecycle events to the shared sign-in coordinator.
///
/// The coordinator owns network reads, storage checkpoints, and submission.
/// Keeping this host at the app root lets those operations run independently
/// of whether the sign-in page has ever been opened.
class DailySignInAutomationOperations {
  const DailySignInAutomationOperations({
    required this.trigger,
    required this.cancelPending,
  });

  final Future<void> Function() trigger;
  final void Function() cancelPending;
}

final dailySignInAutomationOperationsProvider =
    Provider<DailySignInAutomationOperations>((ref) {
      return DailySignInAutomationOperations(
        trigger: () =>
            ref.read(dailySignInControllerProvider.notifier).triggerAutomatic(),
        cancelPending: () => ref
            .read(dailySignInControllerProvider.notifier)
            .cancelAutomaticPending(),
      );
    });

class DailySignInAutomationHost extends ConsumerStatefulWidget {
  const DailySignInAutomationHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DailySignInAutomationHost> createState() =>
      _DailySignInAutomationHostState();
}

class _DailySignInAutomationHostState
    extends ConsumerState<DailySignInAutomationHost>
    with WidgetsBindingObserver {
  bool _isForeground = true;
  bool _queued = false;
  bool _running = false;
  int _requestRevision = 0;
  int _foregroundGeneration = 0;
  int? _runningGeneration;
  VerifiedProfileOwner? _runningOwner;
  late final DailySignInAutomationOperations _operations;

  @override
  void initState() {
    super.initState();
    _operations = ref.read(dailySignInAutomationOperationsProvider);
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _isForeground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    // A restored account may already be verified before the first build. A
    // login event in that first frame wins over this initial fallback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_requestRevision == 0) _requestTrigger();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (!resumed) {
      if (_isForeground) {
        _isForeground = false;
        _foregroundGeneration += 1;
        _queued = false;
        _operations.cancelPending();
      }
      return;
    }
    if (_isForeground) return;
    _isForeground = true;
    _requestTrigger();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_running) {
      _operations.cancelPending();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VerifiedProfileOwner?>(verifiedProfileOwnerProvider, (
      previous,
      next,
    ) {
      if (previous == next) return;
      if (previous != null) {
        _operations.cancelPending();
      }
      if (next != null) _requestTrigger();
    });
    return widget.child;
  }

  void _requestTrigger() {
    if (!mounted || !_isForeground) return;
    final owner = ref.read(verifiedProfileOwnerProvider);
    if (owner == null) return;
    _requestRevision += 1;
    if (_running) {
      // A different owner, or a resumed run after a background cancellation,
      // needs its own fresh read once the old coordinator flight has settled.
      if (owner != _runningOwner ||
          _runningGeneration != _foregroundGeneration) {
        _queued = true;
      }
      return;
    }
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      if (!mounted || !_queued) return;
      _queued = false;
      if (!_isForeground) return;
      final currentOwner = ref.read(verifiedProfileOwnerProvider);
      if (currentOwner == null) return;
      unawaited(_trigger(currentOwner));
    });
  }

  Future<void> _trigger(VerifiedProfileOwner owner) async {
    _running = true;
    _runningOwner = owner;
    _runningGeneration = _foregroundGeneration;
    try {
      await _operations.trigger();
    } catch (_) {
      // A startup task must not interrupt the shell. The coordinator exposes
      // storage and read failures on the sign-in page.
    } finally {
      _running = false;
      _runningOwner = null;
      _runningGeneration = null;
      if (mounted && _queued) {
        _queued = false;
        _requestTrigger();
      }
    }
  }
}
