import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../inline/forum_body_inline_paragraph_layout.dart';
import '../inline/forum_body_inline_span_content.dart';
import '../inline/forum_body_inline_paint_row.dart';
import '../inline/forum_body_emphasis_mark.dart';
import '../inline/forum_body_text_band_content.dart';
import '../inline/forum_body_text_band_layout.dart';
import 'forum_body_native_paragraph_layout.dart';
import 'forum_body_paragraph_content.dart';
import 'forum_body_paragraph_layout.dart';
import 'forum_body_paragraph_row.dart';
import 'forum_body_first_line_indent.dart';
import '../inline/forum_body_native_space_span.dart';
import 'forum_body_text_band_cache_key.dart';
import 'forum_body_text_layout.dart';

part 'forum_body_text_picture.dart';
part 'forum_body_text_picture_input.dart';
part 'forum_body_text_picture_dependencies.dart';

/// Content cannot fit the total budget; pinned pressure may clear when visible
/// leases release. Callers must not spin/restart a source traversal for either.
enum ForumBodyParagraphBudgetFailure { content, pinned }

/// Pure native-input cost for composition, without live ownership. Bytes are
/// an estimate of layout plus reserved paint, never measured native/GPU memory.
typedef ForumBodyNativeInputCost = ({Object identity, int estimatedBytes});

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
  /// One empty, single-run source-free font row under this admission model.
  /// Hosts may reserve temporary font measurements alongside visible pages.
  static const sourceFreeFontEstimatedBytes = 4096 + 256 + 112;

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
  // Only a live entry's last supplied band identity is indexed. This cannot
  // retain evicted entries or bypass current scaler/gutter admission.
  final _bandHints = Map<ForumBodyTextBandContent, _LayoutEntry>.identity();
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
            : entry.layout is _TextPictureLayout
            ? 1
            : 0),
  );
  bool get isClosed => _closed;

  ForumBodyEmphasisMarkLease acquireEmphasisMark({
    required ForumBodyEmphasisMarkInput input,
    TextScaler textScaler = TextScaler.noScaling,
  }) => _acquireEmphasisMark(input, textScaler, true)!;

  ForumBodyEmphasisMarkLease? tryAcquireEmphasisMarkCached({
    required ForumBodyEmphasisMarkInput input,
    TextScaler textScaler = TextScaler.noScaling,
  }) => _acquireEmphasisMark(input, textScaler, false);

  ForumBodyEmphasisMarkLease? _acquireEmphasisMark(
    ForumBodyEmphasisMarkInput input,
    TextScaler scaler,
    bool allowBuild,
  ) {
    if (_closed) throw StateError('Paragraph cache is closed');
    final scaled = ForumBodyEmphasisMarkLayout.resolveScale(input, scaler);
    if (_closed) throw StateError('Paragraph cache is closed');
    final entry = _acquireEntry(
      key: _EmphasisMarkKey(input, scaled),
      allowBuild: allowBuild,
      minimumBytes: input.estimatedInputBytes + 112,
      reservedGeometryBytes: 112,
      build: () => ForumBodyEmphasisMarkLayout.create(
        input: input,
        scaledFontSize: scaled,
      ),
    );
    return entry == null
        ? null
        : ForumBodyEmphasisMarkLease._(this, entry, input);
  }

  /// A prepared text scene shares this owner's entry/byte budget. A miss never
  /// records or shapes; the cooperative preparation owns recording separately.
  ForumBodyTextPictureLease? tryAcquireTextPicture(
    ForumBodyTextPictureInput input,
  ) {
    if (_closed) throw StateError('Paragraph cache is closed');
    final entry = _acquireEntry(
      key: input,
      allowBuild: false,
      minimumBytes: input.estimatedBytes,
      build: () => throw StateError('Cached text picture cannot build'),
      countAsPicture: true,
    );
    return entry == null
        ? null
        : ForumBodyTextPictureLease._(this, entry, input);
  }

  ForumBodyTextPictureLease _adoptTextPicture(
    ForumBodyTextPictureInput input,
    _TextPictureTicket ticket,
    bool Function() isCurrent,
  ) {
    if (_closed) throw StateError('Paragraph cache is closed');
    final measured = input.estimatedInputBytes + ticket.bytes;
    final entry = _acquireEntry(
      key: input,
      allowBuild: true,
      minimumBytes: measured > input.estimatedBytes
          ? measured
          : input.estimatedBytes,
      build: () => _TextPictureLayout(ticket.take()),
      countAsPicture: true,
      isCurrent: isCurrent,
    )!;
    return ForumBodyTextPictureLease._(this, entry, input);
  }

  ForumBodyTextLease _aliasTextLease(ForumBodyTextLease lease) {
    if (!ownsLease(lease) || !lease.layout.isPaintPrepared) {
      throw StateError('Text picture requires current prepared text');
    }
    final entry = lease._entry;
    final alias = switch (lease) {
      ForumBodyParagraphLease() => ForumBodyParagraphLease._(
        this,
        entry,
        lease.content,
      ),
      ForumBodyTextBandChildLease() => ForumBodyTextBandChildLease._(
        this,
        entry,
        lease.bandContent,
        lease.childIndex,
        (entry.layout as ForumBodyTextBandLayout).view(lease.childIndex),
      ),
    };
    entry.leases++;
    _leases++;
    return alias;
  }

  ForumBodyEmphasisMarkLease _aliasEmphasisMarkLease(
    ForumBodyEmphasisMarkLease lease,
  ) {
    if (!ownsLease(lease)) throw StateError('Emphasis mark owner is retired');
    lease._entry.leases++;
    _leases++;
    return ForumBodyEmphasisMarkLease._(this, lease._entry, lease.input);
  }

  ForumBodyInlineParagraphLease _aliasInlineLease(
    ForumBodyInlineParagraphLease lease,
  ) {
    if (!ownsLease(lease) || !lease.layout.isPaintPrepared) {
      throw StateError('Inline picture requires current prepared text');
    }
    lease._entry.leases++;
    _leases++;
    return ForumBodyInlineParagraphLease._(this, lease._entry, lease.content);
  }

  /// Proves the supplied live handle belongs to this reading owner. Does not
  /// acquire an alias, touch the LRU or invoke native/user callbacks.
  bool ownsLease(ForumBodyNativeParagraphLease lease) =>
      !_closed &&
      identical(lease._owner, this) &&
      lease.isActive &&
      !lease._entry.layout.isDisposed;

  ForumBodyTextPictureLease _aliasPictureLease(
    ForumBodyTextPictureLease lease,
  ) {
    if (!ownsLease(lease)) throw StateError('Nested picture owner is retired');
    lease._entry.leases++;
    _leases++;
    return ForumBodyTextPictureLease._(this, lease._entry, lease.input);
  }

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
    double? rowIsolationPitch,
  }) => _acquire(
    content: content,
    width: width,
    textScaler: textScaler,
    allowBuild: true,
    rowIsolationPitch: rowIsolationPitch,
  )!;

  /// A cache miss never shapes. A returned lease has the usual ownership;
  /// invalid inputs and owner retirement still fail before any cache access.
  ForumBodyParagraphLease? tryAcquireCached({
    required ForumBodyParagraphContent content,
    required double width,
    TextScaler textScaler = TextScaler.noScaling,
    double? rowIsolationPitch,
  }) => _acquire(
    content: content,
    width: width,
    textScaler: textScaler,
    allowBuild: false,
    rowIsolationPitch: rowIsolationPitch,
  );

  ForumBodyParagraphLease? _acquire({
    required ForumBodyParagraphContent content,
    required double width,
    required TextScaler textScaler,
    required bool allowBuild,
    double? rowIsolationPitch,
  }) {
    if (_closed) throw StateError('Paragraph cache is closed');
    final scales = ForumBodyParagraphLayout.validateInputs(
      content: content,
      width: width,
      textScaler: textScaler,
      rowIsolationPitch: rowIsolationPitch,
    );
    // Caller-provided TextScaler runs during validation and native shaping.
    if (_closed) throw StateError('Paragraph cache is closed');
    final key = _LayoutKey(content, width, scales, rowIsolationPitch);
    final entry = _acquireEntry(
      key: key,
      allowBuild: allowBuild,
      minimumBytes:
          _minimumEstimatedBytes(content) +
          key.indentBytes +
          key.isolationBytes,
      build: () => ForumBodyParagraphLayout.create(
        content: content,
        width: width,
        textScaler: textScaler,
        rowIsolationPitch: rowIsolationPitch,
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
    double? rowIsolationPitch,
  }) => _acquireInline(
    content: content,
    width: width,
    dimensions: dimensions,
    textScaler: textScaler,
    layoutMode: layoutMode,
    rowIsolationPitch: rowIsolationPitch,
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
    double? rowIsolationPitch,
  }) => _acquireInline(
    content: content,
    width: width,
    dimensions: dimensions,
    textScaler: textScaler,
    layoutMode: layoutMode,
    rowIsolationPitch: rowIsolationPitch,
    allowBuild: false,
  );

  ForumBodyInlineParagraphLease? _acquireInline({
    required ForumBodyInlineSpanContent content,
    required double width,
    required List<PlaceholderDimensions> dimensions,
    required TextScaler textScaler,
    required ForumBodyParagraphLayoutMode layoutMode,
    required double? rowIsolationPitch,
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
      rowIsolationPitch: rowIsolationPitch,
    );
    if (_closed) throw StateError('Paragraph cache is closed');
    final key = _InlineLayoutKey(
      content,
      width,
      scales,
      snapshot,
      layoutMode,
      rowIsolationPitch,
    );
    final entry = _acquireEntry(
      key: key,
      allowBuild: allowBuild,
      minimumBytes:
          _minimumInlineEstimatedBytes(content) +
          key.indentBytes +
          key.isolationBytes,
      build: () => ForumBodyInlineParagraphLayout.create(
        content: content,
        width: width,
        dimensions: snapshot,
        textScaler: textScaler,
        layoutMode: layoutMode,
        rowIsolationPitch: rowIsolationPitch,
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
    final key = _bandKey(content, resolved.scales, resolved.gutter);
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
    _rememberBand(entry, content);
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

  ForumBodyTextBandCacheKey _bandKey(
    ForumBodyTextBandContent content,
    Map<double, double> scales,
    double gutter,
  ) {
    final entry = _bandHints[content];
    if (entry != null && !entry.retired) {
      final key = entry.key as ForumBodyTextBandCacheKey;
      if (key.gutter == gutter &&
          key.scales.length == scales.length &&
          key.scales.every((scale) => scales[scale.$1] == scale.$2)) {
        return key;
      }
    }
    return ForumBodyTextBandCacheKey(content, scales, gutter);
  }

  void _rememberBand(_LayoutEntry entry, ForumBodyTextBandContent content) {
    final previous = entry.bandHint;
    if (previous != null &&
        !identical(previous, content) &&
        identical(_bandHints[previous], entry)) {
      _bandHints.remove(previous);
    }
    entry.bandHint = content;
    _bandHints[content] = entry;
  }

  /// Prepare one actual text view. Ordinary paragraphs need no work; isolated
  /// paragraphs stage and discard their first native drawing. Band children
  /// retain their admitted drawing through the existing path below.
  bool prepareTextPaint(ForumBodyTextLease lease) {
    if (!ownsLease(lease)) throw StateError('Text lease is retired or foreign');
    if (lease is ForumBodyTextBandChildLease) {
      return prepareBandChildPaint(lease);
    }
    final paragraph = lease as ForumBodyParagraphLease;
    if (paragraph.layout.isPaintPrepared) return false;
    if (_preparingPicture) throw StateError('Picture preparation is reentrant');
    _preparingPicture = true;
    try {
      final recorded = paragraph.layout.preparePaint();
      if (!ownsLease(lease)) throw StateError('Text lease is retired');
      if (recorded) _pictureBuilds++;
      return recorded;
    } finally {
      _preparingPicture = false;
    }
  }

  /// Stage and discard the first drawing of an actual isolated mixed parent,
  /// just as for isolated text. Ordinary parents need no recording work.
  bool prepareInlineParentPaint(ForumBodyInlineParagraphLease lease) {
    if (!ownsLease(lease)) {
      throw StateError('Inline parent is retired or foreign');
    }
    if (lease.layout.isPaintPrepared) return false;
    if (_preparingPicture) throw StateError('Picture preparation is reentrant');
    _preparingPicture = true;
    try {
      final recorded = lease.layout.preparePaint();
      if (!ownsLease(lease)) throw StateError('Inline parent is retired');
      if (recorded) _pictureBuilds++;
      return recorded;
    } finally {
      _preparingPicture = false;
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
    bool countAsPicture = false,
    bool Function()? isCurrent,
    int reservedGeometryBytes = 0,
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
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Native request is retired');
      }
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
      if (!countAsPicture) _builds++;
      if (_closed) throw StateError('Paragraph cache is closed');
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Native request is retired');
      }
      // Single-character font resources can reserve their known one-line
      // geometry before shaping; unknown paragraph rows are still added here.
      final geometryBytes =
          built.lineCount * (built is ForumBodyTextBandLayout ? 96 : 112);
      final bytes =
          minimumBytes +
          (geometryBytes > reservedGeometryBytes
              ? geometryBytes - reservedGeometryBytes
              : 0) +
          (built is ForumBodyInlineParagraphLayout
              ? built.fragmentFrameBytes
              : 0);
      // TextScaler is caller code: a nested request can acquire another entry
      // while the engine shapes. Recheck actual pins before admission/eviction.
      _makeRoom(bytes, newEntry: true);
      // Native disposal observers may cancel this transaction without closing
      // its shared cache. A retired recorder must not refill that cache late.
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Native request is retired');
      }
      entry = _LayoutEntry(built, bytes, key);
      _bytes += bytes;
      _entries[key] = entry;
      installed = true;
      if (countAsPicture) _pictureBuilds++;
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
  ForumBodyParagraphBudgetProbe createBudgetProbe({
    bool captureInputEstimates = false,
  }) {
    if (_closed) throw StateError('Paragraph cache is closed');
    return ForumBodyParagraphBudgetProbe._(this, captureInputEstimates);
  }

  void _release(_LayoutEntry entry, {bool discardIfUnused = false}) {
    if (entry.retired) return;
    entry.leases--;
    _leases--;
    try {
      if (discardIfUnused &&
          entry.leases == 0 &&
          identical(_entries[entry.key], entry)) {
        _entries.remove(entry.key);
        _retire(entry);
      }
    } finally {
      _budgetChanged();
    }
  }

  void _budgetChanged() {
    _budgetRevision++;
    _budgetEvents?.add(_budgetRevision);
  }

  void _retire(_LayoutEntry entry) {
    if (entry.retired) return;
    entry.retired = true;
    final hint = entry.bandHint;
    if (hint != null && identical(_bandHints[hint], entry)) {
      _bandHints.remove(hint);
    }
    entry.bandHint = null;
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
  ForumBodyParagraphBudgetProbe._(this._cache, this._captureInputEstimates);
  final bool _captureInputEstimates;
  ForumBodyParagraphCache? _cache;
  final _bytesByKey = <Object, int>{};
  final _inputEstimates = <Object, int>{};
  int _bytes = 0;

  /// Immutable native-input identities only, for numeric page admission. The
  /// keys retain no cache, lease or painter and do not authorize visible use.
  Set<Object> snapshotNativeIdentities() {
    if (_cache == null || _cache!.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    return Set.unmodifiable(_bytesByKey.keys.map(_NativeInputIdentity.new));
  }

  /// Stable pre-paint inputs, independent of resident picture growth or cache
  /// eviction. Request row counts remain the caller's explicit known minimum;
  /// composition uses exact single-line children and the actual parent lease.
  List<ForumBodyNativeInputCost> snapshotNativeEstimates() {
    if (_cache == null || _cache!.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    if (!_captureInputEstimates) {
      throw StateError('Native input estimates were not enabled');
    }
    return List.unmodifiable([
      for (final entry in _inputEstimates.entries)
        (
          identity: _NativeInputIdentity(entry.key),
          estimatedBytes: entry.value,
        ),
    ]);
  }

  /// Include a caller-owned prefix using its actual cache key and retained
  /// bytes. Aliases deduplicate with later requests; no new lease is acquired.
  void includeLease(ForumBodyNativeParagraphLease lease) {
    final cache = _cache;
    if (cache == null || !cache.ownsLease(lease)) {
      throw StateError('Paragraph budget prefix is retired or foreign');
    }
    _include(
      cache,
      lease._entry.key,
      lease._entry.bytes,
      inputEstimate: lease._entry.initialBytes,
    );
  }

  void includeTextPicture(ForumBodyTextPictureInput input) {
    final cache = _cache;
    if (cache == null || cache.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    _include(cache, input, input.estimatedBytes);
  }

  void includeEmphasisMark({
    required ForumBodyEmphasisMarkInput input,
    required TextScaler textScaler,
  }) {
    final cache = _cache;
    if (cache == null || cache.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    final scaled = ForumBodyEmphasisMarkLayout.resolveScale(input, textScaler);
    if (!identical(_cache, cache) || cache.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    _include(
      cache,
      _EmphasisMarkKey(input, scaled),
      input.estimatedInputBytes + 112,
    );
  }

  void include({
    required ForumBodyParagraphContent content,
    required double width,
    required int minimumLineCount,
    required TextScaler textScaler,
    double? rowIsolationPitch,
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
      rowIsolationPitch: rowIsolationPitch,
    );
    // TextScaler is caller code and may re-enter owner/cursor retirement.
    if (!identical(_cache, cache) || cache.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    final key = _LayoutKey(content, width, scales, rowIsolationPitch);
    _include(
      cache,
      key,
      _minimumEstimatedBytes(content) +
          key.indentBytes +
          key.isolationBytes +
          minimumLineCount * 96,
      inputEstimate:
          _minimumEstimatedBytes(content) +
          key.indentBytes +
          key.isolationBytes +
          minimumLineCount * 112,
    );
  }

  void includeInline({
    required ForumBodyInlineSpanContent content,
    required double width,
    required List<PlaceholderDimensions> dimensions,
    required int minimumLineCount,
    required TextScaler textScaler,
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
    double? rowIsolationPitch,
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
      rowIsolationPitch: rowIsolationPitch,
    );
    if (!identical(_cache, cache) || cache.isClosed) {
      throw StateError('Paragraph budget probe is retired');
    }
    final key = _InlineLayoutKey(
      content,
      width,
      scales,
      snapshot,
      layoutMode,
      rowIsolationPitch,
    );
    _include(
      cache,
      key,
      _minimumInlineEstimatedBytes(content) +
          key.indentBytes +
          key.isolationBytes +
          minimumLineCount * 96,
      // Both line-frame arrays and optional trim/allocation arrays are bounded
      // by these pure input counts; no paint or native request is performed.
      inputEstimate:
          _minimumInlineEstimatedBytes(content) +
          key.indentBytes +
          key.isolationBytes +
          minimumLineCount * 128 +
          content.projection.atoms.length * 9,
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
      cache._bandKey(content, resolved.scales, resolved.gutter),
      forumBodyTextBandMinimumBytes(content) +
          (content.contexts.length * 2 - 1) * 96,
    );
  }

  void _include(
    ForumBodyParagraphCache cache,
    Object key,
    int bytes, {
    int? inputEstimate,
  }) {
    final estimate = inputEstimate ?? bytes;
    if (_captureInputEstimates && estimate > (_inputEstimates[key] ?? 0)) {
      _inputEstimates[key] = estimate;
    }
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
    _inputEstimates.clear();
    _bytes = 0;
  }
}

int _minimumEstimatedBytes(ForumBodyParagraphContent content) =>
    4096 +
    content.projection.text.length * 96 +
    content.runs.length * 256 +
    (content.paintLayer == ForumBodyParagraphPaintLayer.all ? 0 : 16);

int _minimumInlineEstimatedBytes(ForumBodyInlineSpanContent content) =>
    4096 +
    content.projection.display.text.length * 96 +
    content.runs.length * 256 +
    content.projection.atoms.length * 256 +
    (content.paintLayer == ForumBodyParagraphPaintLayer.all ? 0 : 16);

sealed class ForumBodyNativeParagraphLease {
  ForumBodyNativeParagraphLease._(this._owner, this._entry);
  final ForumBodyParagraphCache _owner;
  final _LayoutEntry _entry;
  bool _released = false;
  bool get isActive => !_released && !_entry.retired;

  /// Pure opaque input identity. It identifies a deduplicated cache entry,
  /// never a logical handle or an independently projected source context.
  Object get nativeInputIdentity {
    if (!isActive) throw StateError('Native paragraph lease is retired');
    return _entry.nativeInputIdentity;
  }

  /// Captured native layout admission, including its reserved paint capacity.
  /// Later picture growth is enforced by the cache and does not rewrite pages.
  int get nativeLayoutEstimatedBytes {
    if (!isActive) throw StateError('Native paragraph lease is retired');
    return _entry.initialBytes;
  }

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

/// Decoration resources expose neither source content nor text-selection API.
final class ForumBodyEmphasisMarkLease extends ForumBodyNativeParagraphLease {
  ForumBodyEmphasisMarkLease._(super.owner, super.entry, this.input)
    : super._();
  final ForumBodyEmphasisMarkInput input;
  ForumBodyEmphasisMarkLayout get layout {
    if (!isActive) throw StateError('Emphasis mark lease is retired');
    return _entry.layout as ForumBodyEmphasisMarkLayout;
  }
}

final class ForumBodyParagraphLease extends ForumBodyTextLease {
  ForumBodyParagraphLease._(super.owner, super.entry, this.content) : super._();

  /// Current box/role/interaction metadata, separate from cached native input.
  @override
  final ForumBodyParagraphContent content;

  /// Exact current source/request qualification without acquisition, cache
  /// mutation or shaping. A caller scaler can retire this handle while sampled.
  bool matchesNativeInputs({
    required ForumBodyParagraphContent content,
    required double width,
    required TextScaler textScaler,
    double? rowIsolationPitch,
  }) {
    if (!isActive) throw StateError('Paragraph lease is retired');
    final scales = ForumBodyParagraphLayout.validateInputs(
      content: content,
      width: width,
      textScaler: textScaler,
      rowIsolationPitch: rowIsolationPitch,
    );
    if (!isActive) {
      throw StateError('Paragraph lease retired during validation');
    }
    return identical(this.content, content) &&
        _entry.key == _LayoutKey(content, width, scales, rowIsolationPitch);
  }

  /// Qualifies a natural/isolated pair without acquiring or reshaping it.
  /// Equal native keys alone cannot prove the current source or cache owner.
  bool hasSameSourceAndInputsExceptRowIsolation(
    ForumBodyParagraphLease other,
  ) =>
      hasSameActiveOwner(other) &&
      identical(content, other.content) &&
      (_entry.key as _LayoutKey)._hasSameTextInputs(
        other._entry.key as _LayoutKey,
      );

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

  /// Exact current source/request qualification, using the same immutable
  /// slot snapshot and native key as acquire/probe. Never acquires or shapes.
  bool matchesNativeInputs({
    required ForumBodyInlineSpanContent content,
    required double width,
    required List<PlaceholderDimensions> dimensions,
    required TextScaler textScaler,
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
    double? rowIsolationPitch,
  }) {
    if (!isActive) throw StateError('Inline paragraph lease is retired');
    final snapshot = List<PlaceholderDimensions>.unmodifiable(dimensions);
    final scales = ForumBodyInlineParagraphLayout.validateInputs(
      content: content,
      width: width,
      dimensions: snapshot,
      textScaler: textScaler,
      layoutMode: layoutMode,
      rowIsolationPitch: rowIsolationPitch,
    );
    if (!isActive) {
      throw StateError('Inline paragraph lease retired during validation');
    }
    return identical(this.content, content) &&
        _entry.key ==
            _InlineLayoutKey(
              content,
              width,
              scales,
              snapshot,
              layoutMode,
              rowIsolationPitch,
            );
  }

  /// Current cache/source and all actual text/slot/scaler inputs, excluding only
  /// the explicit isolation pitch. A numeric layout/key alone cannot bind rows.
  bool hasSameSourceAndInputsExceptRowIsolation(
    ForumBodyInlineParagraphLease other,
  ) =>
      hasSameActiveOwner(other) &&
      identical(content, other.content) &&
      (_entry.key as _InlineLayoutKey)._hasSameTextInputs(
        other._entry.key as _InlineLayoutKey,
      );

  /// Same current owner/source, font/paint/scale/mode/pitch and slot widths.
  /// Only slot height/baseline may differ. This does not verify the resulting
  /// native rows, trim or target child dimensions; a reflow reference must.
  bool hasSameSourceAndInputsExceptSlotVerticalGeometry(
    ForumBodyInlineParagraphLease other,
  ) {
    if (!hasSameActiveOwner(other) || !identical(content, other.content)) {
      return false;
    }
    final a = _entry.key as _InlineLayoutKey,
        b = other._entry.key as _InlineLayoutKey;
    return a.rowIsolationPitch == b.rowIsolationPitch &&
        a._hasSameTextInputs(b, compareSlotVerticalGeometry: false);
  }

  /// Drop a provisional shape only when this is its last handle. Existing
  /// aliases keep their actual layout and ordinary cache lifetime unchanged.
  void releaseProvisional() {
    if (_released) return;
    _released = true;
    _owner._release(_entry, discardIfUnused: true);
  }

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

/// Opaque equality token: callers cannot mutate internal key tables or retain
/// the cache entry through it. Repeated row admission reuses the captured hash.
final class _NativeInputIdentity {
  _NativeInputIdentity(this._key);
  final Object _key;
  late final int _hash = _key.hashCode;
  @override
  int get hashCode => _hash;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _NativeInputIdentity && _key == other._key;
}

final class _EmphasisMarkKey {
  const _EmphasisMarkKey(this.input, this.scaled);
  final ForumBodyEmphasisMarkInput input;
  final double scaled;
  @override
  bool operator ==(Object other) =>
      other is _EmphasisMarkKey &&
      input == other.input &&
      scaled == other.scaled;
  @override
  int get hashCode =>
      Object.hash(ForumBodyEmphasisMarkLayout.revision, input, scaled);
}

final class _LayoutEntry {
  _LayoutEntry(this.layout, this.bytes, this.key) : initialBytes = bytes;
  final ForumBodyNativeParagraphLayout layout;
  final Object key;
  late final Object nativeInputIdentity = _NativeInputIdentity(key);
  final int initialBytes;
  int bytes;
  int leases = 0;
  bool retired = false;
  ForumBodyTextBandContent? bandHint;
}

/// Complete process-local native input, including baked paint. Actual scaled
/// sizes distinguish nonlinear strategies without relying on scaler equality
/// or the deprecated single scale factor. This key is never persisted.
final class _LayoutKey {
  _LayoutKey(
    ForumBodyParagraphContent content,
    double requestWidth,
    Map<double, double> scales,
    this.rowIsolationPitch,
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
      paintLayer = content.paintLayer,
      layoutMode = content.layoutMode,
      align = content.style.textAlign,
      direction = content.style.textDirection,
      indentAdvance = resolveForumBodyFirstLineIndent(
        content,
        requestWidth,
        scales,
      ),
      scales = _sortedScales(scales);
  final ForumBodyIdentity identity;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final int backendRevision;
  final int projectionRevision;
  final HtmlDisplayTextProjection projection;
  final TextSpan span;
  final ForumBodyParagraphPaintLayer paintLayer;
  final ForumBodyParagraphLayoutMode layoutMode;
  final TextAlign align;
  final TextDirection direction;
  final double width;
  final double indentAdvance;
  final double? rowIsolationPitch;
  int get isolationBytes => rowIsolationPitch == null ? 0 : 32;
  int get indentBytes => indentAdvance > 0
      ? ForumBodyNativeSpaceSpan.nonBreakingText.length * 96
      : 0;
  final List<(double, double)> scales;

  @override
  bool operator ==(Object other) =>
      other is _LayoutKey &&
      rowIsolationPitch == other.rowIsolationPitch &&
      _hasSameTextInputs(other);

  bool _hasSameTextInputs(_LayoutKey other) =>
      identity == other.identity &&
      path == other.path &&
      fontRevision == other.fontRevision &&
      styleRevision == other.styleRevision &&
      backendRevision == other.backendRevision &&
      projectionRevision == other.projectionRevision &&
      projection.hasSameSourceMapping(other.projection) &&
      span == other.span &&
      paintLayer == other.paintLayer &&
      layoutMode == other.layoutMode &&
      align == other.align &&
      direction == other.direction &&
      width == other.width &&
      indentAdvance == other.indentAdvance &&
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
    paintLayer,
    layoutMode,
    align,
    direction,
    width,
    indentAdvance,
    rowIsolationPitch,
    Object.hashAll(scales),
  );
}

final class _InlineLayoutKey {
  _InlineLayoutKey(
    ForumBodyInlineSpanContent content,
    double requestWidth,
    Map<double, double> scales,
    List<PlaceholderDimensions> dimensions,
    ForumBodyParagraphLayoutMode layoutMode,
    double? rowIsolationPitch,
  ) : this._(
        content,
        requestWidth,
        scales,
        dimensions,
        layoutMode,
        content.resolveFirstLineIndent(requestWidth, scales, layoutMode),
        rowIsolationPitch,
      );

  _InlineLayoutKey._(
    ForumBodyInlineSpanContent content,
    double requestWidth,
    Map<double, double> scales,
    List<PlaceholderDimensions> dimensions,
    this.layoutMode,
    this.indentAdvance,
    this.rowIsolationPitch,
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
      paintLayer = content.paintLayer,
      projectionRevision = HtmlDisplayTextProjection.revision,
      inlineRevision = HtmlInlineTextProjection.revision,
      projection = content.projectionForLayout(layoutMode),
      span = content.projection.hasSoftSpaces || indentAdvance > 0
          ? content.textSpanWithDimensions(
              dimensions,
              firstLineIndent: indentAdvance > requestWidth
                  ? requestWidth
                  : indentAdvance,
            )
          : content.textSpan,
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
  final ForumBodyParagraphPaintLayer paintLayer;
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
  final double indentAdvance;
  final double? rowIsolationPitch;
  int get isolationBytes => rowIsolationPitch == null ? 0 : 32;
  int get indentBytes => indentAdvance > 0
      ? ForumBodyNativeSpaceSpan.nonBreakingText.length * 96
      : 0;

  @override
  bool operator ==(Object other) =>
      other is _InlineLayoutKey &&
      rowIsolationPitch == other.rowIsolationPitch &&
      _hasSameTextInputs(other);

  bool _hasSameTextInputs(
    _InlineLayoutKey other, {
    bool compareSlotVerticalGeometry = true,
  }) =>
      identity == other.identity &&
      path == other.path &&
      fontRevision == other.fontRevision &&
      styleRevision == other.styleRevision &&
      backendRevision == other.backendRevision &&
      layoutRevision == other.layoutRevision &&
      inputRevision == other.inputRevision &&
      paintLayer == other.paintLayer &&
      projectionRevision == other.projectionRevision &&
      inlineRevision == other.inlineRevision &&
      projection.hasSameMapping(other.projection) &&
      span == other.span &&
      layoutMode == other.layoutMode &&
      align == other.align &&
      direction == other.direction &&
      width == other.width &&
      indentAdvance == other.indentAdvance &&
      listEquals(scales, other.scales) &&
      (compareSlotVerticalGeometry
          ? listEquals(dimensions, other.dimensions)
          : _hasSameSlotWidths(other));

  bool _hasSameSlotWidths(_InlineLayoutKey other) {
    if (dimensions.length != other.dimensions.length) return false;
    for (var i = 0; i < dimensions.length; i++) {
      if (dimensions[i].$1 != other.dimensions[i].$1) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    identity,
    path,
    fontRevision,
    styleRevision,
    backendRevision,
    layoutRevision,
    inputRevision,
    paintLayer,
    projectionRevision,
    inlineRevision,
    projection.mappingHash,
    span,
    layoutMode,
    align,
    direction,
    width,
    indentAdvance,
    Object.hashAll(scales),
    Object.hashAll(dimensions),
    rowIsolationPitch,
  );
}

List<(double, double)> _sortedScales(Map<double, double> scales) =>
    (scales.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        .map((entry) => (entry.key, entry.value))
        .toList(growable: false);
