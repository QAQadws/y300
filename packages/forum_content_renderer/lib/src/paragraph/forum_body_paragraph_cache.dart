import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import 'forum_body_paragraph_content.dart';
import 'forum_body_paragraph_layout.dart';

final class ForumBodyParagraphBudgetException implements Exception {
  const ForumBodyParagraphBudgetException();
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
  final _entries = <_LayoutKey, _LayoutEntry>{};
  int _bytes = 0;
  int _leases = 0;
  int _builds = 0;
  int _hits = 0;
  bool _closed = false;

  int get entryCount => _entries.length;
  int get estimatedRetainedBytes => _bytes;
  int get activeLeases => _leases;
  int get layoutBuildCount => _builds;
  int get hitCount => _hits;
  bool get isClosed => _closed;

  ForumBodyParagraphLease acquire({
    required ForumBodyParagraphContent content,
    required double width,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (_closed) throw StateError('Paragraph cache is closed');
    final scales = ForumBodyParagraphLayout.validateInputs(
      content: content,
      width: width,
      textScaler: textScaler,
    );
    final key = _LayoutKey(content, width, scales);
    var entry = _entries.remove(key);
    if (entry != null && entry.layout.isDisposed) {
      _retire(entry);
      entry = null;
    }
    if (entry != null) {
      _hits++;
    } else {
      final minimumBytes =
          4096 +
          content.projection.text.length * 96 +
          content.runs.length * 256;
      var pinnedBytes = 0;
      var pinnedEntries = 0;
      for (final resident in _entries.values) {
        if (resident.leases > 0) {
          pinnedEntries++;
          pinnedBytes += resident.bytes;
        }
      }
      if (pinnedEntries >= maxEntries ||
          minimumBytes > maxEstimatedBytes - pinnedBytes) {
        throw const ForumBodyParagraphBudgetException();
      }
      final layout = ForumBodyParagraphLayout.create(
        content: content,
        width: width,
        textScaler: textScaler,
      );
      _builds++;
      final bytes = minimumBytes + layout.lines.length * 96;
      if (bytes > maxEstimatedBytes - pinnedBytes) {
        layout.dispose();
        throw const ForumBodyParagraphBudgetException();
      }
      while (_entries.length >= maxEntries ||
          _bytes + bytes > maxEstimatedBytes) {
        _LayoutKey? victim;
        for (final candidate in _entries.entries) {
          if (candidate.value.leases == 0) {
            victim = candidate.key;
            break;
          }
        }
        if (victim == null) {
          layout.dispose();
          throw const ForumBodyParagraphBudgetException();
        }
        _retire(_entries.remove(victim)!);
      }
      entry = _LayoutEntry(layout, bytes, key);
      _bytes += bytes;
    }
    _entries[entry.key] = entry;
    entry.leases++;
    _leases++;
    return ForumBodyParagraphLease._(this, entry, content);
  }

  void _release(_LayoutEntry entry) {
    if (entry.retired) return;
    entry.leases--;
    _leases--;
  }

  void _retire(_LayoutEntry entry) {
    entry.retired = true;
    _bytes -= entry.bytes;
    _leases -= entry.leases;
    entry.leases = 0;
    entry.layout.dispose();
  }

  void clearUnpinned() {
    final victims = _entries.keys
        .where((key) => _entries[key]!.leases == 0)
        .toList();
    for (final key in victims) {
      _retire(_entries.remove(key)!);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final entry in _entries.values) {
      _retire(entry);
    }
    _entries.clear();
  }
}

final class ForumBodyParagraphLease {
  ForumBodyParagraphLease._(this._owner, this._entry, this.content);
  final ForumBodyParagraphCache _owner;
  final _LayoutEntry _entry;

  /// Current box/role/interaction metadata, separate from cached native input.
  final ForumBodyParagraphContent content;
  bool _released = false;
  bool get isActive => !_released && !_entry.retired;
  ForumBodyParagraphLayout get layout {
    if (!isActive) throw StateError('Paragraph lease is retired');
    return _entry.layout;
  }

  void release() {
    if (_released) return;
    _released = true;
    _owner._release(_entry);
  }
}

final class _LayoutEntry {
  _LayoutEntry(this.layout, this.bytes, this.key);
  final ForumBodyParagraphLayout layout;
  final _LayoutKey key;
  final int bytes;
  int leases = 0;
  bool retired = false;
}

/// Complete process-local native input, including baked paint. Actual scaled
/// sizes distinguish nonlinear strategies without relying on scaler equality
/// or the deprecated single scale factor. This key is never persisted.
final class _LayoutKey {
  _LayoutKey(
    ForumBodyParagraphContent content,
    this.width,
    Map<double, double> scales,
  ) : identity = content.identity,
      path = content.path,
      fontRevision = content.fontRevision,
      styleRevision = content.styleRevision,
      backendRevision = ForumBodyParagraphLayout.backendRevision,
      projectionRevision = HtmlDisplayTextProjection.revision,
      span = content.textSpan,
      align = content.style.textAlign,
      direction = content.style.textDirection,
      scales = (scales.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((entry) => (entry.key, entry.value))
          .toList(growable: false);
  final ForumBodyIdentity identity;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final int backendRevision;
  final int projectionRevision;
  final TextSpan span;
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
      span == other.span &&
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
    span,
    align,
    direction,
    width,
    Object.hashAll(scales),
  );
}
