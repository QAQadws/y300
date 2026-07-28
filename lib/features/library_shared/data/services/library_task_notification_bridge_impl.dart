import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_bridge.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';

/// Default [LibraryTaskNotificationBridge].
///
/// Watches the favorite and comic progress channels on the hub and mirrors the
/// task-specific progress into a system notification. Source filtering keeps
/// each notification tied to one task type even though several mutation sources
/// can surface on the same module channel.
class DefaultLibraryTaskNotificationBridge
    implements LibraryTaskNotificationBridge {
  DefaultLibraryTaskNotificationBridge({
    required LibraryTaskProgressHub hub,
    required LibraryTaskNotificationService notificationService,
  }) : _hub = hub,
       _notificationService = notificationService;

  final LibraryTaskProgressHub _hub;
  final LibraryTaskNotificationService _notificationService;

  // Each bridged channel binds one module + mutation source to a notification
  // identity. Presentation copy is resolved from the current locale snapshot.
  late final List<_BridgedChannel> _channels = <_BridgedChannel>[
    _BridgedChannel(
      key: LibraryTaskNotificationKey.favoriteSync,
      source: LibraryMutationSource.favoriteSync,
      listenable: _hub.progressFor(LibraryModuleKey.favorite),
    ),
    _BridgedChannel(
      key: LibraryTaskNotificationKey.comicSearchQueue,
      source: LibraryMutationSource.comicSearchQueue,
      listenable: _hub.progressFor(LibraryModuleKey.comic),
    ),
  ];

  bool _started = false;
  String? _localeId;
  LibraryTaskNotificationTextResolver? _textResolver;

  @override
  void start({
    required String localeId,
    required LibraryTaskNotificationTextResolver textResolver,
  }) {
    final localeChanged = _localeId != localeId;
    _localeId = localeId;
    _textResolver = textResolver;
    if (!_started) {
      _started = true;
      for (final channel in _channels) {
        channel.listener = () => _handleChannel(channel);
        channel.listenable.addListener(channel.listener!);
      }
    }
    for (final channel in _channels) {
      if (localeChanged) {
        channel.lastSignature = null;
      }
      // Emit once so an existing task is reflected and locale changes repost.
      _handleChannel(channel);
    }
  }

  @override
  void dispose() {
    for (final channel in _channels) {
      final listener = channel.listener;
      if (listener != null) {
        channel.listenable.removeListener(listener);
        channel.listener = null;
      }
      if (channel.lastSignature != null) {
        // Best-effort cleanup; errors must not escape disposal.
        unawaited(_clearQuietly(channel.key));
        channel.lastSignature = null;
      }
    }
    _started = false;
    _localeId = null;
    _textResolver = null;
  }

  void _handleChannel(_BridgedChannel channel) {
    final progress = channel.listenable.value;
    final relevant =
        progress != null &&
        progress.active &&
        progress.source == channel.source;

    if (!relevant) {
      if (channel.lastSignature != null) {
        channel.lastSignature = null;
        unawaited(_clearQuietly(channel.key));
      }
      return;
    }

    final textResolver = _textResolver;
    if (textResolver == null) {
      return;
    }

    final signature = _signatureOf(progress);
    // Skip redundant updates so we do not re-post an unchanged notification.
    if (signature == channel.lastSignature) {
      return;
    }
    channel.lastSignature = signature;
    final text = textResolver(progress);
    unawaited(
      _showQuietly(
        LibraryTaskNotification(
          key: channel.key,
          title: text.title,
          body: text.body,
          current: progress.current,
          total: progress.total,
        ),
      ),
    );
  }

  String _signatureOf(LibraryShelfTaskProgress progress) {
    return '${_localeId ?? ''}|${progress.code.name}|${progress.subject ?? ''}'
        '|${progress.estimatedDuration?.inMilliseconds ?? ''}'
        '|${progress.current}|${progress.total}';
  }

  Future<void> _showQuietly(LibraryTaskNotification notification) async {
    try {
      await _notificationService.showOrUpdate(notification);
    } catch (_) {
      // Notification delivery is best-effort; never break task execution.
    }
  }

  Future<void> _clearQuietly(LibraryTaskNotificationKey key) async {
    try {
      await _notificationService.clear(key);
    } catch (_) {
      // Ignore: clearing is best-effort.
    }
  }
}

class _BridgedChannel {
  _BridgedChannel({
    required this.key,
    required this.source,
    required this.listenable,
  });

  final LibraryTaskNotificationKey key;
  final LibraryMutationSource source;
  final ValueListenable<LibraryShelfTaskProgress?> listenable;

  VoidCallback? listener;
  String? lastSignature;
}
