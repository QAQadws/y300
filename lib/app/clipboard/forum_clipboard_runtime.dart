import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/core/clipboard/self_copy_fingerprint_registry.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';

import 'forum_clipboard_coordinator.dart';
import 'forum_clipboard_route_observer.dart';

final forumClipboardRouteObserverProvider =
    Provider<ForumClipboardRouteObserver>((ref) {
      final observer = ForumClipboardRouteObserver();
      ref.onDispose(observer.dispose);
      return observer;
    });

final forumClipboardRuntimeProvider = Provider<ForumClipboardRuntime>((ref) {
  final runtime = ForumClipboardRuntime(
    readText: ref.read(clipboardTextReaderProvider).readText,
    selfCopyRegistry: ref.read(clipboardSelfCopyFingerprintRegistryProvider),
  );
  final subscription = ref
      .read(yamiboSessionStoreProvider)
      .identityChanges
      .listen((_) => runtime.changeOwner());
  ref.onDispose(() {
    unawaited(subscription.cancel());
    runtime.dispose();
  });
  return runtime;
});

/// Process-owned history survives shell rebuilds. No page/context, clipboard
/// text or URL is retained beyond the coordinator's current candidate.
final class ForumClipboardRuntime extends ChangeNotifier {
  ForumClipboardRuntime({
    required Future<String?> Function() readText,
    required SelfCopyFingerprintRegistry selfCopyRegistry,
  }) {
    coordinator = ForumClipboardCoordinator(
      readText: readText,
      selfCopyRegistry: selfCopyRegistry,
      onChanged: (_) => _publish(),
    );
  }

  late final ForumClipboardCoordinator coordinator;
  Object _owner = Object();
  Object? _host;
  bool _enabled = false;
  bool _coldRequested = false;
  bool _wafBusy = false;
  bool _updateBlocked = false;
  bool? _updateConfigured;
  bool _disposed = false;
  bool _notificationScheduled = false;

  bool get isUnblocked => !_wafBusy && !_updateBlocked;
  bool get needsColdCheck => !_coldRequested;

  Object attach() {
    coordinator.cancelOperations();
    final token = Object();
    _host = token;
    coordinator.updateEligibility(
      available: false,
      enabled: _enabled,
      owner: _owner,
    );
    return token;
  }

  bool owns(Object token) => !_disposed && identical(token, _host);

  void detach(Object token) {
    if (!owns(token)) return;
    _host = null;
    coordinator.cancelOperations();
    coordinator.updateEligibility(
      available: false,
      enabled: _enabled,
      owner: _owner,
    );
  }

  void updateEligibility(
    Object token, {
    required bool enabled,
    required bool available,
  }) {
    if (!owns(token)) return;
    _enabled = enabled;
    coordinator.updateEligibility(
      available: available && isUnblocked,
      enabled: enabled,
      owner: _owner,
    );
  }

  void requestColdCheck(Object token) {
    if (!owns(token) || _coldRequested) return;
    _coldRequested = true;
    coordinator.requestCheck();
  }

  void changeOwner() {
    if (_disposed) return;
    _owner = Object();
    coordinator.updateEligibility(
      available: false,
      enabled: _enabled,
      owner: _owner,
    );
    _publish();
  }

  void configureUpdatePrompt(bool enabled) {
    if (_updateConfigured == enabled) return;
    _updateConfigured = enabled;
    setUpdateBlocked(enabled);
  }

  void setWafBusy(bool busy) {
    if (_wafBusy == busy || _disposed) return;
    _wafBusy = busy;
    _gateChanged();
  }

  void setUpdateBlocked(bool blocked) {
    if (_updateBlocked == blocked || _disposed) return;
    _updateBlocked = blocked;
    _gateChanged();
  }

  void _gateChanged() {
    if (!isUnblocked) {
      // These gates retire optional detection, not an already confirmed open.
      // Its locator may itself need the shared WAF recovery to finish.
      coordinator.updateEligibility(
        available: false,
        enabled: _enabled,
        owner: _owner,
      );
    }
    _publish();
  }

  void _publish() {
    if (_disposed || _notificationScheduled) return;
    // UpgradeAlert can evaluate during build. Retire work synchronously above,
    // but publish widget changes after that frame to respect Flutter's contract.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      _notificationScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notificationScheduled = false;
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _host = null;
    coordinator.dispose();
    super.dispose();
  }
}
