import 'package:flutter/foundation.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/image_session/reader_image_session.dart';

enum ReaderImageSessionStatus { idle, diskReady, decoded, failed }

@immutable
class ReaderImageSessionEntry {
  const ReaderImageSessionEntry({
    required this.readerOwnerId,
    required this.itemId,
    required this.imageIndex,
    required this.sourceUrl,
    required this.cacheKey,
    required this.generation,
    this.localPath,
    this.status = ReaderImageSessionStatus.idle,
    this.decoded = false,
    this.failureReason,
  });

  final String readerOwnerId;
  final String itemId;
  final int imageIndex;
  final String sourceUrl;
  final String cacheKey;
  final int generation;
  final String? localPath;
  final ReaderImageSessionStatus status;
  final bool decoded;
  final String? failureReason;

  ReaderImageSessionEntry copyWith({
    String? localPath,
    ReaderImageSessionStatus? status,
    bool? decoded,
    String? failureReason,
    bool clearFailureReason = false,
  }) {
    return ReaderImageSessionEntry(
      readerOwnerId: readerOwnerId,
      itemId: itemId,
      imageIndex: imageIndex,
      sourceUrl: sourceUrl,
      cacheKey: cacheKey,
      generation: generation,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      decoded: decoded ?? this.decoded,
      failureReason: clearFailureReason
          ? null
          : (failureReason ?? this.failureReason),
    );
  }
}

class ReaderImageSessionBinding
    implements ValueListenable<ReaderImageSessionEntry> {
  const ReaderImageSessionBinding._({
    required ReaderImageSessionStore store,
    required ValueNotifier<ReaderImageSessionEntry> notifier,
  }) : _store = store,
       _notifier = notifier;

  final ReaderImageSessionStore _store;
  final ValueNotifier<ReaderImageSessionEntry> _notifier;

  @override
  ReaderImageSessionEntry get value => _notifier.value;

  @override
  void addListener(VoidCallback listener) => _notifier.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);

  bool promoteLocalPath(String? localPath) {
    return _store.promoteLocalPath(
      readerOwnerId: value.readerOwnerId,
      itemId: value.itemId,
      generation: value.generation,
      localPath: localPath,
    );
  }
}

/// Session-local image preparation state.
///
/// It stores paths and preparation status only. Decoded bitmaps remain owned by
/// Flutter's ImageCache. Every binding is scoped by owner and generation so a
/// late result from a previous chapter cannot mutate the current reader UI.
class ReaderImageSessionStore {
  String? _readerOwnerId;
  int _generation = 0;
  final Map<String, _ReaderImageSessionSlot> _slots =
      <String, _ReaderImageSessionSlot>{};
  bool _disposed = false;

  String? get readerOwnerId => _readerOwnerId;
  int get generation => _generation;

  void startSession({
    required String readerOwnerId,
    required int generation,
    required Iterable<ContinuousImageItem> items,
  }) {
    if (_disposed) {
      return;
    }
    if (_readerOwnerId == readerOwnerId && _generation == generation) {
      return;
    }
    for (final slot in _slots.values) {
      slot.notifier.dispose();
    }
    _slots.clear();
    _readerOwnerId = readerOwnerId;
    _generation = generation;
    for (final item in items) {
      _slots[item.id] = _createSlot(item);
    }
  }

  ReaderImageSessionBinding bindingFor(
    ContinuousImageItem item, {
    String? initialLocalPath,
  }) {
    if (_disposed || _readerOwnerId != item.ownerId) {
      throw StateError(
        'Reader image session is not active for ${item.ownerId}',
      );
    }
    final slot = _slots.putIfAbsent(item.id, () => _createSlot(item));
    final normalizedPath = _normalize(initialLocalPath);
    if (normalizedPath != null && slot.notifier.value.localPath == null) {
      slot.notifier.value = slot.notifier.value.copyWith(
        localPath: normalizedPath,
        status: ReaderImageSessionStatus.diskReady,
        clearFailureReason: true,
      );
    }
    return slot.binding;
  }

  bool applyPreloadResult({
    required String readerOwnerId,
    required String itemId,
    required int generation,
    required String sourceUrl,
    required String? cacheKey,
    required ReaderImageSessionPreloadKind kind,
    required ForumImagePrecacheResult result,
  }) {
    if (!_isCurrent(readerOwnerId, generation)) {
      return false;
    }
    final slot = _slots[itemId];
    if (slot == null || !_matches(slot.notifier.value, sourceUrl, cacheKey)) {
      return false;
    }
    final current = slot.notifier.value;
    final localPath = _normalize(result.localPath);
    if (!result.success && (current.localPath != null || current.decoded)) {
      return true;
    }
    final decoded =
        current.decoded ||
        result.decoded ||
        kind == ReaderImageSessionPreloadKind.decoded;
    final status = result.success
        ? (decoded
              ? ReaderImageSessionStatus.decoded
              : ReaderImageSessionStatus.diskReady)
        : ReaderImageSessionStatus.failed;
    final next = current.copyWith(
      localPath: localPath,
      status: status,
      decoded: decoded,
      failureReason: result.success ? null : result.failureReason,
      clearFailureReason: result.success,
    );
    if (next.localPath == current.localPath &&
        next.status == current.status &&
        next.decoded == current.decoded &&
        next.failureReason == current.failureReason) {
      return true;
    }
    slot.notifier.value = next;
    return true;
  }

  bool promoteLocalPath({
    required String readerOwnerId,
    required String itemId,
    required int generation,
    required String? localPath,
  }) {
    final normalizedPath = _normalize(localPath);
    if (normalizedPath == null || !_isCurrent(readerOwnerId, generation)) {
      return false;
    }
    final slot = _slots[itemId];
    if (slot == null) {
      return false;
    }
    final current = slot.notifier.value;
    if (current.localPath == normalizedPath &&
        current.status != ReaderImageSessionStatus.failed) {
      return true;
    }
    slot.notifier.value = current.copyWith(
      localPath: normalizedPath,
      status: current.decoded
          ? ReaderImageSessionStatus.decoded
          : ReaderImageSessionStatus.diskReady,
      clearFailureReason: true,
    );
    return true;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final slot in _slots.values) {
      slot.notifier.dispose();
    }
    _slots.clear();
    _readerOwnerId = null;
  }

  _ReaderImageSessionSlot _createSlot(ContinuousImageItem item) {
    final notifier = ValueNotifier<ReaderImageSessionEntry>(
      ReaderImageSessionEntry(
        readerOwnerId: _readerOwnerId ?? item.ownerId,
        itemId: item.id,
        imageIndex: item.index,
        sourceUrl: item.url,
        cacheKey: item.cacheKey,
        generation: _generation,
      ),
    );
    return _ReaderImageSessionSlot(
      notifier: notifier,
      binding: ReaderImageSessionBinding._(store: this, notifier: notifier),
    );
  }

  bool _isCurrent(String readerOwnerId, int generation) {
    return !_disposed &&
        _readerOwnerId == readerOwnerId &&
        _generation == generation;
  }

  bool _matches(
    ReaderImageSessionEntry entry,
    String sourceUrl,
    String? cacheKey,
  ) {
    final normalizedKey = _normalize(cacheKey);
    return entry.sourceUrl == sourceUrl &&
        (normalizedKey == null ||
            entry.cacheKey.isEmpty ||
            entry.cacheKey == normalizedKey);
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _ReaderImageSessionSlot {
  const _ReaderImageSessionSlot({
    required this.notifier,
    required this.binding,
  });

  final ValueNotifier<ReaderImageSessionEntry> notifier;
  final ReaderImageSessionBinding binding;
}
