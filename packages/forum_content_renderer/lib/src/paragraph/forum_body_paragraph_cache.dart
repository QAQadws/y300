import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../inline/forum_body_inline_paragraph_layout.dart';
import '../inline/forum_body_inline_span_content.dart';
import '../inline/forum_body_text_band_content.dart';
import '../inline/forum_body_text_band_layout.dart';
import 'forum_body_native_paragraph_layout.dart';
import 'forum_body_paragraph_content.dart';
import 'forum_body_paragraph_layout.dart';
import 'forum_body_text_band_cache_key.dart';
import 'forum_body_text_layout.dart';

/// Content cannot fit the total budget; pinned pressure may clear when visible
/// leases release. Callers must not spin/restart a source traversal for either.
enum ForumBodyParagraphBudgetFailure { content, pinned }

final class ForumBodyParagraphBudgetException implements Exception {
  const ForumBodyParagraphBudgetException(
    this.failure, {
    this.requiredEstimatedBytes,
    this.requiredAdditionalEntries = 1,
  });
  final ForumBodyParagraphBudgetFailure failure;
  final int? requiredEstimatedBytes;
  final int requiredAdditionalEntries;
  @override
  String toString() => 'ForumBodyParagraphBudgetException(${failure.name})';
}

/// The session owner supplies both limits. Bytes are an admission estimate,
/// not measured engine/font/GPU memory; calibrate the estimate on device.
/// Visible/neighbor views hold leases and cannot be evicted by background work.
final class ForumBodyParagraphCache {
  ForumBodyParagraphCache({
    required this.maxEntries,
    required this.maxEstimatedBytes,
  }) {
    if (maxEntries <= 0 || maxEstimatedBytes <= 0) {
      throw ArgumentError('Invalid paragraph cache budget');
    }
  }
  final int maxEntries;
  final int maxEstimatedBytes;
  final _entries = <Object, _LayoutEntry>{};
  final _buildingKeys = <Object>{};
  int _bytes = 0;
  int _leases = 0;
  int _builds = 0;
  int _hits = 0;
  int _pictureBuilds = 0;
  bool _preparingPicture = false;
  bool _closed = false;
  int _budgetRevision = 0;
  StreamController<int>? _budgetEvents;

  int get entryCount => _entries.length;
  int get estimatedRetainedBytes => _bytes;
  int get activeLeases => _leases;
  int get layoutBuildCount => _builds;
  int get hitCount => _hits;
  int get pictureBuildCount => _pictureBuilds;
  int get preparedPictureCount => _entries.values.fold<int>(
    0,
    (sum, entry) =>
        sum +
        (entry.layout is ForumBodyTextBandLayout
            ? (entry.layout as ForumBodyTextBandLayout).preparedPictureCount
            : 0),
  );
  bool get isClosed => _closed;

  /// Proves the supplied live handle belongs to this reading owner. Does not
  /// acquire an alias, touch the LRU or invoke native/user callbacks.
  bool ownsLease(ForumBodyNativeParagraphLease lease) =>
      !_closed &&
      identical(lease._owner, this) &&
      lease.isActive &&
      !lease._entry.layout.isDisposed;

  /// Monotonic evidence that a lease was released or this owner retired.
  /// Callers must still retry admission; aliases need not free a native entry.
  int get budgetRevision => _budgetRevision;

  /// Lazy, asynchronous broadcast avoids re-entering cache mutation from a
  /// release callback. Subscribe and then recheck budgetRevision to avoid a
  /// lost wake-up. Acquisition alone is not a reason to retry a blocked input.
  Stream<int> get budgetChanges => _closed
      ? const Stream<int>.empty()
      : (_budgetEvents ??= StreamController<int>.broadcast()).stream;

  ForumBodyParagraphLease acquire({
    required ForumBodyParagraphContent content,
    required double width,
    TextScaler textScaler = TextScaler.noScaling,
  }) => _acquire(
    content: content,
    width: width,
    textScaler: textScaler,
    allowBuild: true,
  )!;

  /// A cache miss never shapes. A returned lease has the usual ownership;
  /// invalid inputs and owner retirement still fail before any cache access.
  ForumBodyParagraphLease? tryAcquireCached({
    required ForumBodyParagraphContent content,
    required double width,
    TextScaler textScaler = TextScaler.noScaling,
  }) => _acquire(
    content: content,
    width: width,
    textScaler: textScaler,
    allowBuild: false,
  );

  ForumBodyParagraphLease? _acquire({
    required ForumBodyParagraphContent content,
    required double width,
    required TextScaler textScaler,
    required bool allowBuild,
  }) {
    if (_closed) throw StateError('Paragraph cache is closed');
    final scales = ForumBodyParagraphLayout.validateInputs(
      content: content,
      width: width,
      textScaler: textScaler,
    );
    // Caller-provided TextScaler runs during validation and native shaping.
    if (_closed) throw StateError('Paragraph cache is closed');
    final key = _LayoutKey(content, width, scales);
    final entry = _acquireEntry(
      key: key,
      allowBuild: allowBuild,
      minimumBytes: _minimumEstimatedBytes(content),
      build: () => ForumBodyParagraphLayout.create(
        content: content,
        width: width,
        textScaler: textScaler,
      ),
    );
    return entry == null
        ? null
        : ForumBodyParagraphLease._(this, entry, content);
  }

  ForumBodyInlineParagraphLease acquireInline({
    required ForumBodyInlineSpanContent content,
    required double width,
    required List<PlaceholderDimensions> dimensions,
    TextScaler textScaler = TextScaler.noScaling,
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) => _acquireInline(
    content: content,
    width: width,
    dimensions: dimensions,
    textScaler: textScaler,
    layoutMode: layoutMode,
    allowBuild: true,
  )!;

  /// Never builds a parent or a child on a miss. Consumers prepare native work
  /// cooperatively before acquiring a visible view from this same owner.
  ForumBodyInlineParagraphLease? tryAcquireInlineCached({
    required ForumBodyInlineSpanContent content,
    required double width,
    required List<PlaceholderDimensions> dimensions,
    TextScaler textScaler = TextScaler.noScaling,
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) => _acquireInline(
    content: content,
    width: width,
    dimensions: dimensions,
    textScaler: textScaler,
    layoutMode: layoutMode,
    allowBuild: false,
  );

  ForumBodyInlineParagraphLease? _acquireInline({
    required ForumBodyInlineSpanContent content,
    required double width,
    required List<PlaceholderDimensions> dimensions,
    required TextScaler textScaler,
    required ForumBodyParagraphLayoutMode layoutMode,
    required bool allowBuild,
  }) {
    if (_closed) throw StateError('Paragraph cache is closed');
    final snapshot = List<PlaceholderDimensions>.unmodifiable(dimensions);
    final scales = ForumBodyInlineParagraphLayout.validateInputs(
      content: content,
      width: width,
      dimensions: snapshot,
      textScaler: textScaler,
      layoutMode: layoutMode,
    );
    if (_closed) throw StateError('Paragraph cache is closed');
    final key = _InlineLayoutKey(content, width, scales, snapshot, layoutMode);
    final entry = _acquireEntry(
      key: key,
      allowBuild: allowBuild,
      minimumBytes: _minimumInlineEstimatedBytes(content),
      build: () => ForumBodyInlineParagraphLayout.create(
        content: content,
        width: width,
        dimensions: snapshot,
        textScaler: textScaler,
        layoutMode: layoutMode,
      ),
    );
    return entry == null
        ? null
        : ForumBodyInlineParagraphLease._(this, entry, content);
  }

  ForumBodyTextBandChildLease acquireBandChild({
    required ForumBodyTextBandContent content,
    required int childIndex,
    TextScaler textScaler = TextScaler.noScaling,
    double? gutter,
  }) => _acquireBandChild(
    content: content,
    childIndex: childIndex,
    textScaler: textScaler,
    gutter: gutter,
    allowBuild: true,
  )!;

  /// A miss does no native work, including picture recording. Every child pins
  /// the same band entry in this owner's existing entry and byte budgets.
  ForumBodyTextBandChildLease? tryAcquireBandChildCached({
    required ForumBodyTextBandContent content,
    required int childIndex,
    TextScaler textScaler = TextScaler.noScaling,
    double? gutter,
  }) => _acquireBandChild(
    content: content,
    childIndex: childIndex,
    textScaler: textScaler,
    gutter: gutter,
    allowBuild: false,
  );

  ForumBodyTextBandChildLease? _acquireBandChild({
    required ForumBodyTextBandContent content,
    required int childIndex,
    required TextScaler textScaler,
    required double? gutter,
    required bool allowBuild,
  }) {
    if (_closed) throw StateError('Paragraph cache is closed');
    RangeError.checkValidIndex(childIndex, content.contexts, 'childIndex');
    final resolved = ForumBodyTextBandLayout.validateInputs(
      content: content,
      textScaler: textScaler,
      gutter: gutter,
    );
    if (_closed) throw StateError('Paragraph cache is closed');
    final key = ForumBodyTextBandCacheKey(
      content,
      resolved.scales,
      resolved.gutter,
    );
    final entry = _acquireEntry(
      key: key,
      allowBuild: allowBuild,
      minimumBytes: forumBodyTextBandMinimumBytes(content),
      build: () => ForumBodyTextBandLayout.create(
        content: content,
        textScaler: textScaler,
        gutter: resolved.gutter,
      ),
    );
    if (entry == null) return null;
    try {
      return ForumBodyTextBandChildLease._(
        this,
        entry,
        content,
        childIndex,
        (entry.layout as ForumBodyTextBandLayout).view(childIndex),
      );
    } catch (_) {
      _release(entry);
      rethrow;
    }
  }

  /// Cooperative work outside paint: record one child, admit its measured
  /// display-list cost, then publish. A rejection drops only the new ticket.
  bool prepareBandChildPaint(ForumBodyTextBandChildLease lease) {
    if (!ownsLease(lease)) {
      throw StateError('Text band lease is retired or foreign');
    }
    final entry = lease._entry;
    final band = entry.layout as ForumBodyTextBandLayout;
    if (band.isPaintPrepared(lease.childIndex)) return false;
    if (_preparingPicture) throw StateError('Picture preparation is reentrant');
    _preparingPicture = true;
    ForumBodyTextBandPaint? ticket;
    try {
      ticket = band.recordPaint(lease.childIndex);
      if (!ownsLease(lease)) throw StateError('Text band lease is retired');
      final reserve = (entry.key as ForumBodyTextBandCacheKey).pictureReserve;
      final extra = band.approximatePictureBytes - reserve;
      final target = entry.initialBytes + (extra > 0 ? extra : 0);
      final growth = target > entry.bytes ? target - entry.bytes : 0;
      if (target > maxEstimatedBytes) {
        throw ForumBodyParagraphBudgetException(
          ForumBodyParagraphBudgetFailure.content,
          requiredEstimatedBytes: target,
        );
      }
      _makeRoom(growth, newEntry: false);
      if (!ownsLease(lease)) throw StateError('Text band lease is retired');
      // No caller code runs between admission and adoption. The native ticket
      // remains owned here until the band explicitly consumes it.
      _bytes += growth;
      entry.bytes += growth;
      band.adoptPaint(ticket);
      _pictureBuilds++;
      return true;
    } finally {
      try {
        ticket?.close();
      } finally {
        _preparingPicture = false;
      }
    }
  }

  _LayoutEntry? _acquireEntry({
    required Object key,
    required bool allowBuild,
    required int minimumBytes,
    required ForumBodyNativeParagraphLayout Function() build,
  }) {
    if (_buildingKeys.contains(key)) {
      throw StateError('Native paragraph shaping is reentrant');
    }
    var entry = _entries[key];
    if (entry != null && !entry.layout.isDisposed) {
      _entries.remove(key);
      _entries[key] = entry;
      _hits++;
      entry.leases++;
      _leases++;
      return entry;
    }
    _buildingKeys.add(key);
    ForumBodyNativeParagraphLayout? built;
    var installed = false;
    try {
      if (entry != null) {
        _entries.remove(key);
        _retire(entry);
      }
      if (_closed) throw StateError('Paragraph cache is closed');
      if (!allowBuild) return null;
      final pinned = _pinnedFootprint();
      if (minimumBytes > maxEstimatedBytes) {
        throw ForumBodyParagraphBudgetException(
          ForumBodyParagraphBudgetFailure.content,
          requiredEstimatedBytes: minimumBytes,
        );
      }
      if (pinned.entries >= maxEntries ||
          minimumBytes > maxEstimatedBytes - pinned.bytes) {
        throw ForumBodyParagraphBudgetException(
          ForumBodyParagraphBudgetFailure.pinned,
          requiredEstimatedBytes: minimumBytes,
        );
      }
      built = build();
      _builds++;
      if (_closed) throw StateError('Paragraph cache is closed');
      final bytes = minimumBytes + built.lineCount * 96;
      // TextScaler is caller code: a nested request can acquire another entry
      // while the engine shapes. Recheck actual pins before admission/eviction.
      _makeRoom(bytes, newEntry: true);
      entry = _LayoutEntry(built, bytes, key);
      _bytes += bytes;
      _entries[key] = entry;
      installed = true;
      entry.leases++;
      _leases++;
      return entry;
    } finally {
      try {
        if (!installed) built?.dispose();
      } finally {
        _buildingKeys.remove(key);
      }
    }
  }

  void _makeRoom(int bytes, {required bool newEntry}) {
    var evictions = 0;
    while (true) {
      if (_closed) throw StateError('Paragraph cache is closed');
      if (bytes > maxEstimatedBytes) {
        throw ForumBodyParagraphBudgetException(
          ForumBodyParagraphBudgetFailure.content,
          requiredEstimatedBytes: bytes,
        );
      }
      final pinned = _pinnedFootprint();
      if ((newEntry && pinned.entries >= maxEntries) ||
          bytes > maxEstimatedBytes - pinned.bytes) {
        throw ForumBodyParagraphBudgetException(
          ForumBodyParagraphBudgetFailure.pinned,
          requiredEstimatedBytes: bytes,
          requiredAdditionalEntries: newEntry ? 1 : 0,
        );
      }
      if ((!newEntry || _entries.length < maxEntries) &&
          bytes <= maxEstimatedBytes - _bytes) {
        return;
      }
      Object? victim;
      for (final candidate in _entries.entries) {
        if (candidate.value.leases == 0) {
          victim = candidate.key;
          break;
        }
      }
      if (victim == null) {
        throw ForumBodyParagraphBudgetException(
          ForumBodyParagraphBudgetFailure.pinned,
          requiredEstimatedBytes: bytes,
          requiredAdditionalEntries: newEntry ? 1 : 0,
        );
      }
      // Native disposal hooks may reacquire other entries. Bound this one
      // admission even if an observer keeps replenishing unpinned victims.
      if (evictions++ >= maxEntries) {
        throw StateError('Cache eviction is reentrant');
      }
      _retire(_entries.remove(victim)!);
    }
  }

  ({int entries, int bytes}) _pinnedFootprint() {
    var count = 0;
    var bytes = 0;
    for (final entry in _entries.values) {
      if (entry.leases > 0) {
        count++;
        bytes += entry.bytes;
      }
    }
    return (entries: count, bytes: bytes);
  }

  /// Test whether releasing other entries could unblock this rejection. Alias
  /// leases of our own entries add no capacity, and our own footprint plus the
  /// rejected input can already prove an intrinsic page-budget failure.
  bool isBlockedByExternalPins(
    ForumBodyParagraphBudgetException rejection,
    Iterable<ForumBodyNativeParagraphLease> owned,
  ) {
    if (_closed) throw StateError('Paragraph cache is closed');
    if (rejection.failure != ForumBodyParagraphBudgetFailure.pinned) {
      return false;
    }
    final kept = <_LayoutEntry>{};
    for (final lease in owned) {
      if (!ownsLease(lease)) {
        throw StateError('Prepared lease is not active in this cache');
      }
      kept.add(lease._entry);
    }
    final keptBytes = kept.fold<int>(0, (sum, entry) => sum + entry.bytes);
    if (kept.length + rejection.requiredAdditionalEntries > maxEntries ||
        (rejection.requiredEstimatedBytes != null &&
            rejection.requiredEstimatedBytes! >
                maxEstimatedBytes - keptBytes)) {
      return false;
    }
    return _entries.values.any(
      (entry) => entry.leases > 0 && !kept.contains(entry),
    );
  }

  /// Internal transactional-view admission. It only proves lower-bound
  /// impossibility; a successful probe does not reserve or guarantee capacity.
  ForumBodyParagraphBudgetProbe createBudgetProbe() {
    if (_closed) throw StateError('Paragraph cache is closed');
    return ForumBodyParagraphBudgetProbe._(this);
  }

  void _release(_LayoutEntry entry) {
    if (entry.retired) return;
    entry.leases--;
    _leases--;
    _budgetChanged();
  }

  void _budgetChanged() {
    _budgetRevision++;
    _budgetEvents?.add(_budgetRevision);
  }

  void _retire(_LayoutEntry entry) {
    if (entry.retired) return;
    entry.retired = true;
    _bytes -= entry.bytes;
    _leases -= entry.leases;
    entry.leases = 0;
    entry.layout.dispose();
  }

  void clearUnpinned() {
    if (_closed) return;
    final victims = _entries.entries
        .where((item) => item.value.leases == 0)
        .toList();
    Object? failure;
    StackTrace? stack;
    for (final victim in victims) {
      if (identical(_entries[victim.key], victim.value) &&
          victim.value.leases == 0) {
        _entries.remove(victim.key);
        try {
          _retire(victim.value);
        } catch (error, trace) {
          failure ??= error;
          stack ??= trace;
        }
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final entries = _entries.values.toList();
    _entries.clear();
    Object? failure;
    StackTrace? stack;
    for (final entry in entries) {
      try {
        _retire(entry);
      } catch (error, trace) {
        failure ??= error;
        stack ??= trace;
      }
    }
    _budgetChanged();
    final events = _budgetEvents;
    if (events != null) unawaited(events.close());
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }
}

/// Incremental footprint of a view, deduplicated by the actual native key.
/// No shaping, lease, LRU/hit mutation or native object is retained. Close drops
/// both the cache owner and temporary pure keys; callers bound inspected inputs.
final class ForumBodyParagraphBudgetProbe {
  ForumBodyParagraphBudgetProbe._(this._cache);
  ForumBodyParagraphCache? _cache;
  final _bytesByKey = <Object, int>{};
  int _bytes = 0;

  void include({
    required ForumBodyParagraphContent content,
    required double width,
    required int minimumLineCount,
    required TextScaler textScaler,
  }) {
    final cache = _cache;
    if (cache == null || cache.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    if (minimumLineCount < 0) throw ArgumentError.value(minimumLineCount);
    final scales = ForumBodyParagraphLayout.validateInputs(
      content: content,
      width: width,
      textScaler: textScaler,
    );
    // TextScaler is caller code and may re-enter owner/cursor retirement.
    if (!identical(_cache, cache) || cache.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    final key = _LayoutKey(content, width, scales);
    _include(
      cache,
      key,
      _minimumEstimatedBytes(content) + minimumLineCount * 96,
    );
  }

  void includeInline({
    required ForumBodyInlineSpanContent content,
    required double width,
    required List<PlaceholderDimensions> dimensions,
    required int minimumLineCount,
    required TextScaler textScaler,
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) {
    final cache = _cache;
    if (cache == null || cache.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    if (minimumLineCount < 0) throw ArgumentError.value(minimumLineCount);
    final snapshot = List<PlaceholderDimensions>.unmodifiable(dimensions);
    final scales = ForumBodyInlineParagraphLayout.validateInputs(
      content: content,
      width: width,
      dimensions: snapshot,
      textScaler: textScaler,
      layoutMode: layoutMode,
    );
    if (!identical(_cache, cache) || cache.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    final key = _InlineLayoutKey(content, width, scales, snapshot, layoutMode);
    _include(
      cache,
      key,
      _minimumInlineEstimatedBytes(content) + minimumLineCount * 96,
    );
  }

  void includeBandChild({
    required ForumBodyTextBandContent content,
    required int childIndex,
    TextScaler textScaler = TextScaler.noScaling,
    double? gutter,
  }) {
    final cache = _cache;
    if (cache == null || cache.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    RangeError.checkValidIndex(childIndex, content.contexts, 'childIndex');
    final resolved = ForumBodyTextBandLayout.validateInputs(
      content: content,
      textScaler: textScaler,
      gutter: gutter,
    );
    if (!identical(_cache, cache) || cache.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    _include(
      cache,
      ForumBodyTextBandCacheKey(content, resolved.scales, resolved.gutter),
      forumBodyTextBandMinimumBytes(content) +
          (content.contexts.length * 2 - 1) * 96,
    );
  }

  void _include(ForumBodyParagraphCache cache, Object key, int bytes) {
    final resident = cache._entries[key];
    if (resident != null &&
        !resident.layout.isDisposed &&
        resident.bytes > bytes) {
      bytes = resident.bytes;
    }
    final previous = _bytesByKey[key];
    if (previous == null || bytes > previous) {
      _bytesByKey[key] = bytes;
      _bytes += bytes - (previous ?? 0);
    }
    if (_bytesByKey.length > cache.maxEntries ||
        _bytes > cache.maxEstimatedBytes) {
      throw ForumBodyParagraphBudgetException(
        ForumBodyParagraphBudgetFailure.content,
        requiredEstimatedBytes: _bytes,
      );
    }
  }

  void close() {
    _cache = null;
    _bytesByKey.clear();
    _bytes = 0;
  }
}

int _minimumEstimatedBytes(ForumBodyParagraphContent content) =>
    4096 + content.projection.text.length * 96 + content.runs.length * 256;

int _minimumInlineEstimatedBytes(ForumBodyInlineSpanContent content) =>
    4096 +
    content.projection.display.text.length * 96 +
    content.runs.length * 256 +
    content.projection.atoms.length * 256;

sealed class ForumBodyNativeParagraphLease {
  ForumBodyNativeParagraphLease._(this._owner, this._entry);
  final ForumBodyParagraphCache _owner;
  final _LayoutEntry _entry;
  bool _released = false;
  bool get isActive => !_released && !_entry.retired;

  /// Owner proof for aggregate prepared views without exposing the cache or
  /// acquiring another handle. Closed owners and retired aliases never match.
  bool hasSameActiveOwner(ForumBodyNativeParagraphLease other) =>
      identical(_owner, other._owner) &&
      _owner.ownsLease(this) &&
      _owner.ownsLease(other);

  void release() {
    if (_released) return;
    _released = true;
    _owner._release(_entry);
  }
}

/// Current metadata and source-local text contract; native ownership remains
/// in the common cache. A band child never impersonates a whole paragraph.
sealed class ForumBodyTextLease extends ForumBodyNativeParagraphLease {
  ForumBodyTextLease._(super.owner, super.entry) : super._();
  ForumBodyParagraphContent get content;
  ForumBodyTextLayout get layout;
}

final class ForumBodyParagraphLease extends ForumBodyTextLease {
  ForumBodyParagraphLease._(super.owner, super.entry, this.content) : super._();

  /// Current box/role/interaction metadata, separate from cached native input.
  @override
  final ForumBodyParagraphContent content;
  @override
  ForumBodyParagraphLayout get layout {
    if (!isActive) throw StateError('Paragraph lease is retired');
    return _entry.layout as ForumBodyParagraphLayout;
  }
}

final class ForumBodyInlineParagraphLease
    extends ForumBodyNativeParagraphLease {
  ForumBodyInlineParagraphLease._(super.owner, super.entry, this.content)
    : super._();

  /// Always the current child styles/interactions, not a cached engine's input.
  final ForumBodyInlineSpanContent content;
  ForumBodyInlineParagraphLayout get layout {
    if (!isActive) throw StateError('Paragraph lease is retired');
    return _entry.layout as ForumBodyInlineParagraphLayout;
  }
}

final class ForumBodyTextBandChildLease extends ForumBodyTextLease {
  ForumBodyTextBandChildLease._(
    super.owner,
    super.entry,
    this.bandContent,
    this.childIndex,
    this._view,
  ) : super._();
  final ForumBodyTextBandContent bandContent;
  final int childIndex;
  final ForumBodyTextBandChildLayout _view;
  @override
  ForumBodyParagraphContent get content => bandContent.contexts[childIndex];
  @override
  bool get isActive => super.isActive && !_view.isDisposed;
  @override
  ForumBodyTextBandChildLayout get layout {
    if (!isActive) throw StateError('Text band lease is retired');
    return _view;
  }

  @override
  void release() {
    _view.dispose();
    super.release();
  }
}

final class _LayoutEntry {
  _LayoutEntry(this.layout, this.bytes, this.key) : initialBytes = bytes;
  final ForumBodyNativeParagraphLayout layout;
  final Object key;
  final int initialBytes;
  int bytes;
  int leases = 0;
  bool retired = false;
}

/// Complete process-local native input, including baked paint. Actual scaled
/// sizes distinguish nonlinear strategies without relying on scaler equality
/// or the deprecated single scale factor. This key is never persisted.
final class _LayoutKey {
  _LayoutKey(
    ForumBodyParagraphContent content,
    double requestWidth,
    Map<double, double> scales,
  ) : width =
          content.layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine
          ? 0
          : requestWidth,
      identity = content.identity,
      path = content.path,
      fontRevision = content.fontRevision,
      styleRevision = content.styleRevision,
      backendRevision = ForumBodyParagraphLayout.backendRevision,
      projectionRevision = HtmlDisplayTextProjection.revision,
      projection = content.projection,
      span = content.textSpan,
      layoutMode = content.layoutMode,
      align = content.style.textAlign,
      direction = content.style.textDirection,
      scales = _sortedScales(scales);
  final ForumBodyIdentity identity;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final int backendRevision;
  final int projectionRevision;
  final HtmlDisplayTextProjection projection;
  final TextSpan span;
  final ForumBodyParagraphLayoutMode layoutMode;
  final TextAlign align;
  final TextDirection direction;
  final double width;
  final List<(double, double)> scales;

  @override
  bool operator ==(Object other) =>
      other is _LayoutKey &&
      identity == other.identity &&
      path == other.path &&
      fontRevision == other.fontRevision &&
      styleRevision == other.styleRevision &&
      backendRevision == other.backendRevision &&
      projectionRevision == other.projectionRevision &&
      projection.hasSameSourceMapping(other.projection) &&
      span == other.span &&
      layoutMode == other.layoutMode &&
      align == other.align &&
      direction == other.direction &&
      width == other.width &&
      listEquals(scales, other.scales);
  @override
  int get hashCode => Object.hash(
    identity,
    path,
    fontRevision,
    styleRevision,
    backendRevision,
    projectionRevision,
    projection.sourceMappingHash,
    span,
    layoutMode,
    align,
    direction,
    width,
    Object.hashAll(scales),
  );
}

final class _InlineLayoutKey {
  _InlineLayoutKey(
    ForumBodyInlineSpanContent content,
    double requestWidth,
    Map<double, double> scales,
    List<PlaceholderDimensions> dimensions,
    this.layoutMode,
  ) : width = layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine
          ? 0
          : requestWidth,
      identity = content.identity,
      path = content.path,
      fontRevision = content.fontRevision,
      styleRevision = content.styleRevision,
      backendRevision = ForumBodyParagraphLayout.backendRevision,
      layoutRevision = ForumBodyInlineParagraphLayout.revision,
      inputRevision = ForumBodyInlineSpanContent.revision,
      projectionRevision = HtmlDisplayTextProjection.revision,
      inlineRevision = HtmlInlineTextProjection.revision,
      projection = content.projection,
      span = content.textSpan,
      align = content.style.textAlign,
      direction = content.style.textDirection,
      scales = _sortedScales(scales),
      dimensions = dimensions
          .map(
            (item) => (item.size.width, item.size.height, item.baselineOffset!),
          )
          .toList(growable: false);
  final ForumBodyIdentity identity;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final int backendRevision;
  final int layoutRevision;
  final int inputRevision;
  final int projectionRevision;
  final int inlineRevision;
  final HtmlInlineTextProjection projection;
  final TextSpan span;
  final ForumBodyParagraphLayoutMode layoutMode;
  final TextAlign align;
  final TextDirection direction;
  final double width;
  final List<(double, double)> scales;
  final List<(double, double, double)> dimensions;

  @override
  bool operator ==(Object other) =>
      other is _InlineLayoutKey &&
      identity == other.identity &&
      path == other.path &&
      fontRevision == other.fontRevision &&
      styleRevision == other.styleRevision &&
      backendRevision == other.backendRevision &&
      layoutRevision == other.layoutRevision &&
      inputRevision == other.inputRevision &&
      projectionRevision == other.projectionRevision &&
      inlineRevision == other.inlineRevision &&
      projection.hasSameMapping(other.projection) &&
      span == other.span &&
      layoutMode == other.layoutMode &&
      align == other.align &&
      direction == other.direction &&
      width == other.width &&
      listEquals(scales, other.scales) &&
      listEquals(dimensions, other.dimensions);

  @override
  int get hashCode => Object.hash(
    identity,
    path,
    fontRevision,
    styleRevision,
    backendRevision,
    layoutRevision,
    inputRevision,
    projectionRevision,
    inlineRevision,
    projection.mappingHash,
    span,
    layoutMode,
    align,
    direction,
    width,
    Object.hashAll(scales),
    Object.hashAll(dimensions),
  );
}

List<(double, double)> _sortedScales(Map<double, double> scales) =>
    (scales.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        .map((entry) => (entry.key, entry.value))
        .toList(growable: false);
