import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import 'novel_reader_native_preparation_cache.dart';

/// One reading owner across layouts/mode switches. Overlapping layouts have
/// independent budgets so a mounted old page cannot starve its replacement.
/// Font changes invalidate new acquisitions, not old paragraphs on screen.
/// Host releases each handle only after its session and mounted views retire.
final class NovelReaderNativeOwner extends ChangeNotifier {
  NovelReaderNativeOwner({
    Listenable? fontChanges,
    this.maxParagraphEntries = 64,
    this.maxParagraphEstimatedBytes = 16 * 1024 * 1024,
  }) : _fontChanges = fontChanges ?? PaintingBinding.instance.systemFonts {
    if (maxParagraphEntries <= 0 || maxParagraphEstimatedBytes <= 0) {
      throw ArgumentError('Invalid native owner cache budget');
    }
    _fontChanges!.addListener(_fontsChanged);
  }

  final int maxParagraphEntries;
  final int maxParagraphEstimatedBytes;
  final preparationCache = NovelReaderNativePreparationCache();
  Listenable? _fontChanges;
  _CacheGeneration? _current;
  final _retired = <_CacheGeneration>{};
  final _handles = <NovelReaderNativeCacheHandle>{};
  int _fontGeneration = 0;
  bool _closed = false;
  bool _dispatchingFonts = false;

  bool get isClosed => _closed;
  int get fontGeneration => _fontGeneration;
  int get activeCacheHandles => _handles.length;
  int get retainedCacheGenerations =>
      _retired.length + (_current == null ? 0 : 1);

  /// Entry/byte limits apply per live cache generation. At layout/font handoff,
  /// referenced old and replacement caches coexist; this is not native memory.
  int get estimatedRetainedBytes =>
      preparationCache.estimatedRetainedBytes +
      (_current?.cache.estimatedRetainedBytes ?? 0) +
      _retired.fold(
        0,
        (sum, entry) => sum + entry.cache.estimatedRetainedBytes,
      );

  NovelReaderNativeCacheHandle acquireCache({String? layoutKey}) {
    if (_closed) throw StateError('Native reading owner is closed');
    if (layoutKey != null && layoutKey.isEmpty) {
      throw ArgumentError.value(layoutKey, 'layoutKey');
    }
    var entry = _current;
    if (entry != null &&
        layoutKey != null &&
        entry.layoutKey != null &&
        entry.layoutKey != layoutKey &&
        entry.handles > 0) {
      // Old mounted views retain their cache until actual unmount. Waiting for
      // their pins in this cache would deadlock a dense replacement page.
      _retired.add(entry);
      _current = null;
      entry = null;
    }
    entry ??= _CacheGeneration(
      ForumBodyParagraphCache(
        maxEntries: maxParagraphEntries,
        maxEstimatedBytes: maxParagraphEstimatedBytes,
      ),
    );
    _current = entry;
    if (layoutKey != null) entry.layoutKey = layoutKey;
    final selected = entry;
    late final NovelReaderNativeCacheHandle handle;
    handle = NovelReaderNativeCacheHandle._(
      entry.cache,
      _fontGeneration,
      () => _release(selected, handle),
    );
    entry.handles++;
    _handles.add(handle);
    return handle;
  }

  void _release(_CacheGeneration entry, NovelReaderNativeCacheHandle handle) {
    if (!_handles.remove(handle)) return;
    entry.handles--;
    if (!identical(entry, _current) && entry.handles == 0) {
      _retired.remove(entry);
      entry.cache.close();
    }
  }

  void _fontsChanged() {
    if (_closed) return;
    _fontGeneration++;
    final old = _current;
    _current = null;
    for (final handle in _handles) {
      handle._current = false;
    }
    if (old != null) {
      if (old.handles == 0) {
        old.cache.close();
      } else {
        _retired.add(old);
      }
    }
    // Install the new generation before notifying reentrant Host callbacks.
    _dispatchingFonts = true;
    try {
      notifyListeners();
    } finally {
      _dispatchingFonts = false;
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    final fontChanges = _fontChanges;
    _fontChanges = null;
    for (final handle in _handles) {
      handle._retire();
    }
    _handles.clear();
    preparationCache.dispose();
    _current?.cache.close();
    _current = null;
    for (final entry in _retired) {
      entry.cache.close();
    }
    _retired.clear();
    if (_dispatchingFonts) {
      // SDK systemFonts iterates its callback Set directly. Retire resources
      // now, but remove that callback and dispose ChangeNotifier after dispatch.
      scheduleMicrotask(() {
        fontChanges?.removeListener(_fontsChanged);
        super.dispose();
      });
    } else {
      fontChanges?.removeListener(_fontsChanged);
      notifyListeners();
      super.dispose();
    }
  }
}

final class _CacheGeneration {
  _CacheGeneration(this.cache);
  final ForumBodyParagraphCache cache;
  String? layoutKey;
  int handles = 0;
}

/// Cache access for one actual layout lifetime. release is idempotent and
/// never disposes a current warm cache; dispose of the reading owner is terminal.
final class NovelReaderNativeCacheHandle {
  NovelReaderNativeCacheHandle._(
    this.cache,
    this.fontGeneration,
    this._release,
  );
  final ForumBodyParagraphCache cache;
  final int fontGeneration;
  VoidCallback? _release;
  bool _current = true;
  bool get isActive => _release != null && !cache.isClosed;
  bool get isCurrent => isActive && _current;

  void release() {
    final release = _release;
    _release = null;
    _current = false;
    release?.call();
  }

  void _retire() {
    _release = null;
    _current = false;
  }
}
