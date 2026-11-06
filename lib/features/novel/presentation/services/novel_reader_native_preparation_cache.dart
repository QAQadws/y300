import 'dart:async';

import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_source_provenance.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

import '../models/novel_reader_native_prepared_chapter.dart';
import '../models/novel_reader_pagination_exception.dart';
import 'novel_reader_native_diagnostics.dart';
import 'novel_reader_native_preparation_service.dart';
import 'novel_reader_pagination_cancellation.dart';

final class NovelReaderNativePreparationBudgetException implements Exception {
  const NovelReaderNativePreparationBudgetException();
}

/// Owner-scoped pure source data only. Typography, native layouts, contexts and
/// semantic documents are not retained by completed cache entries. A weak
/// semantic identity prevents uncaptured/different origins reusing a warm hit.
final class NovelReaderNativePreparationCache {
  NovelReaderNativePreparationCache({
    this.maxEntries = 4,
    this.maxEstimatedBytes = 16 * 1024 * 1024,
    this.maxInFlight = 4,
  }) {
    if (maxEntries <= 0 || maxEstimatedBytes < 0 || maxInFlight <= 0) {
      throw ArgumentError('Invalid native preparation cache budget');
    }
  }
  final int maxEntries;
  final int maxEstimatedBytes;
  final int maxInFlight;
  final _semanticIds = Expando<int>();
  final _serviceIds = Expando<int>();
  int _nextIdentity = 0;
  final _entries =
      <_Key, ({NovelReaderNativeChapterPreparation value, int bytes})>{};
  final _inFlight = <_Key, _Work>{};
  final _active = <_Work>{};
  int _bytes = 0;
  bool _closed = false;

  bool get isClosed => _closed;
  int get length => _entries.length;
  int get inFlightCount => _active.length;
  int get estimatedRetainedBytes => _bytes;

  Future<NovelReaderNativeChapterPreparation> resolve({
    required NovelReaderNativePreparationService service,
    required String episodeId,
    required String sourceId,
    required String rawHtml,
    required NovelReaderDocument semanticDocument,
    required NovelReaderPaginationCancellationToken cancellation,
    TextConverter converter = const IdentityTextConverter(),
  }) async {
    cancellation.throwIfCancelled();
    if (_closed) throw StateError('Native preparation owner is closed');
    final key = _Key(
      _semanticIds[semanticDocument] ??= ++_nextIdentity,
      _serviceIds[service] ??= ++_nextIdentity,
      episodeId,
      sourceId,
      rawHtml,
      converter.id,
      converter.mode.name,
    );
    cancellation.throwIfCancelled();
    if (_closed) throw StateError('Native preparation owner is closed');
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached.value;
    }
    var work = _inFlight[key];
    if (work == null) {
      if (_active.length >= maxInFlight) {
        throw const NovelReaderNativePreparationBudgetException();
      }
      work = _Work();
      _inFlight[key] = work;
      _active.add(work);
      // Attach an observer before dispatch: all callers may cancel before a
      // terminal owner error, while the shared work must still be observed.
      final wait = cancellation.waitFor(work.result.future);
      unawaited(_prepare(key, work, service, semanticDocument, converter));
      return wait;
    }
    // A layout cancellation owns only its wait, never another caller's work.
    return cancellation.waitFor(work.result.future);
  }

  Future<void> _prepare(
    _Key key,
    _Work work,
    NovelReaderNativePreparationService service,
    NovelReaderDocument semantic,
    TextConverter converter,
  ) async {
    try {
      final value = await service.prepare(
        episodeId: key.episodeId,
        sourceId: key.sourceId,
        rawHtml: key.rawHtml,
        semanticDocument: semantic,
        converter: converter,
        cancellation: work.token,
      );
      work.token.throwIfCancelled();
      if (!_closed && identical(_inFlight[key], work)) {
        _put(key, value);
        if (value is NovelReaderNativePreparedChapter) {
          const NovelReaderNativeDiagnostics().prepared(value.document);
        }
      }
      if (!work.result.isCompleted) work.result.complete(value);
    } catch (error, stack) {
      if (!work.result.isCompleted) work.result.completeError(error, stack);
    } finally {
      if (identical(_inFlight[key], work)) _inFlight.remove(key);
      _active.remove(work);
      work.token.cancel();
    }
  }

  void _put(_Key key, NovelReaderNativeChapterPreparation value) {
    final bytes = _estimate(key, value);
    if (bytes > maxEstimatedBytes) return;
    while (_entries.length >= maxEntries ||
        _bytes + bytes > maxEstimatedBytes) {
      final removed = _entries.remove(_entries.keys.first)!;
      _bytes -= removed.bytes;
    }
    _entries[key] = (value: value, bytes: bytes);
    _bytes += bytes;
  }

  /// Reusable invalidation. Active callers still receive their data, but a
  /// detached old flight cannot remove or fill a newer flight for the same key.
  void clear() {
    _entries.clear();
    _inFlight.clear();
    _bytes = 0;
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    clear();
    for (final work in _active.toList(growable: false)) {
      work.token.cancel();
      if (!work.result.isCompleted) {
        work.result.completeError(
          const NovelReaderPaginationException(
            code: 'paginationCancelled',
            message: 'Native preparation owner retired.',
          ),
        );
      }
    }
    _active.clear();
  }
}

final class _Work {
  final token = NovelReaderPaginationCancellationToken();
  final result = Completer<NovelReaderNativeChapterPreparation>();
}

final class _Key {
  _Key(
    this.semanticId,
    this.serviceId,
    this.episodeId,
    this.sourceId,
    this.rawHtml,
    this.converterId,
    this.mode,
  );
  final int semanticId;
  final int serviceId;
  final String episodeId;
  final String sourceId;
  final String rawHtml;
  final String converterId;
  final String mode;
  final int parserRevision = ForumBodyParser.revision;
  final int provenanceRevision = NovelReaderSourceProvenance.revision;
  @override
  bool operator ==(Object other) =>
      other is _Key &&
      semanticId == other.semanticId &&
      serviceId == other.serviceId &&
      episodeId == other.episodeId &&
      sourceId == other.sourceId &&
      rawHtml == other.rawHtml &&
      converterId == other.converterId &&
      mode == other.mode &&
      parserRevision == other.parserRevision &&
      provenanceRevision == other.provenanceRevision;
  @override
  int get hashCode => Object.hash(
    semanticId,
    serviceId,
    episodeId,
    sourceId,
    rawHtml,
    converterId,
    mode,
    parserRevision,
    provenanceRevision,
  );
}

int _estimate(_Key key, NovelReaderNativeChapterPreparation value) {
  var bytes =
      512 +
      8 * key.rawHtml.length +
      2 * (key.episodeId.length + key.sourceId.length + key.converterId.length);
  if (value is NovelReaderNativePreparedChapter) {
    final map = value.document.sourceMap;
    // Fixed-weight admission estimate, not measured heap/native memory. Raw
    // markup covers retained text/attributes/declarations conservatively; counts
    // cover immutable IR/maps and per-rune coordinate/projection arrays.
    bytes +=
        256 * value.document.parsedNodeCount +
        32 * value.document.elementCounts.length +
        32 * map.runeLength +
        64 * map.rangesByPath.length +
        256 * value.anchors.segments.length;
    for (final path in map.rangesByPath.keys) {
      bytes += 4 * path.length;
    }
    for (final segment in value.anchors.segments) {
      bytes +=
          8 * segment.projection.semanticOffsetsBySourceRuneBoundary.length;
    }
    for (final image in value.anchors.images) {
      bytes +=
          256 +
          2 *
              (image.path.length +
                  image.url.length +
                  image.rawSource.length +
                  (image.anchor.nodeId?.length ?? 0) +
                  (image.anchor.textIdentity?.length ?? 0));
    }
  }
  return bytes;
}
