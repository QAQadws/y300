import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// A complete preparation result is transient; the page retains its manifest
/// and a bounded set of independent chunk documents instead.
final class ThreadDetailPreparedBody {
  const ThreadDetailPreparedBody({
    required this.request,
    required this.document,
  });

  final ForumHtmlPreparationRequest request;
  final ForumHtmlPreparedRenderDocument document;

  int get retainedCodeUnits =>
      document.preparedHtml.length +
      (document.safeDisplayPlan?.chunks.fold<int>(
            0,
            (length, chunk) => length + chunk.html.length,
          ) ??
          0);
}

/// Stable display boundaries survive cache eviction without retaining the
/// prepared HTML, its plan, or the plan's individual HTML strings.
final class ThreadDetailBodyManifest {
  ThreadDetailBodyManifest({
    required this.request,
    required this.kind,
    required List<ThreadDetailBodyChunkManifest> chunks,
  }) : chunks = List.unmodifiable(chunks);

  factory ThreadDetailBodyManifest.fromPrepared(ThreadDetailPreparedBody body) {
    if (!_isSafePreparedBody(body.request.sourceId, body)) {
      throw ArgumentError.value(body, 'body', 'Expected a safe display plan');
    }
    final plan = body.document.safeDisplayPlan!;
    return ThreadDetailBodyManifest(
      request: body.request,
      kind: plan.kind,
      chunks: [
        for (final chunk in plan.chunks)
          ThreadDetailBodyChunkManifest(
            ordinal: chunk.ordinal,
            startUnit: chunk.startUnit,
            endUnit: chunk.endUnit,
            hasTrailingContent: chunk.hasTrailingContent,
            htmlCodeUnits: chunk.html.length,
            fingerprint: _htmlFingerprint(chunk.html),
          ),
      ],
    );
  }

  // request.html refers to the already loaded display post. It is source state,
  // not an extra prepared snapshot, and is excluded from the chunk-cache budget.
  final ForumHtmlPreparationRequest request;
  final ForumHtmlSafeDisplayPlanKind kind;
  final List<ThreadDetailBodyChunkManifest> chunks;

  Object get identity => request.identity;
  int get unitCount => chunks.isEmpty ? 0 : chunks.last.endUnit;

  bool matches(ThreadDetailPreparedBody body) {
    if (identity != body.request.identity ||
        !_isSafePreparedBody(request.sourceId, body)) {
      return false;
    }
    final plan = body.document.safeDisplayPlan!;
    if (kind != plan.kind || chunks.length != plan.chunks.length) return false;
    for (var ordinal = 0; ordinal < chunks.length; ordinal++) {
      final expected = chunks[ordinal];
      final actual = plan.chunks[ordinal];
      if (expected.ordinal != actual.ordinal ||
          expected.startUnit != actual.startUnit ||
          expected.endUnit != actual.endUnit ||
          expected.hasTrailingContent != actual.hasTrailingContent ||
          expected.htmlCodeUnits != actual.html.length ||
          expected.fingerprint != _htmlFingerprint(actual.html)) {
        return false;
      }
    }
    return true;
  }
}

final class ThreadDetailBodyChunkManifest {
  const ThreadDetailBodyChunkManifest({
    required this.ordinal,
    required this.startUnit,
    required this.endUnit,
    required this.hasTrailingContent,
    required this.htmlCodeUnits,
    required this.fingerprint,
  });

  final int ordinal;
  final int startUnit;
  final int endUnit;
  final bool hasTrailingContent;
  final int htmlCodeUnits;
  final String fingerprint;
}

/// This document has no display plan and retains only this chunk's HTML.
final class ThreadDetailPreparedChunk {
  const ThreadDetailPreparedChunk({
    required this.document,
    required this.ordinal,
    required this.hasTrailingContent,
  });

  final ForumHtmlPreparedRenderDocument document;
  final int ordinal;
  final bool hasTrailingContent;

  String get html => document.preparedHtml;
}

/// Display qualification belongs to the page manifest, independently of cache
/// capacity. Eviction removes chunk values without changing the lazy entries.
final class ThreadDetailPreparedBodyStore {
  ThreadDetailPreparedBodyStore({this.maxRetainedCodeUnits = 4 * 1024 * 1024})
    : assert(maxRetainedCodeUnits >= 0);

  final int maxRetainedCodeUnits;
  final _manifests = <String, ThreadDetailBodyManifest>{};
  final _chunks =
      <(ThreadDetailBodyManifest, int), ThreadDetailPreparedChunk>{};
  final _heights = <ThreadDetailBodyManifest, _ChunkHeightLedger>{};
  int _retainedCodeUnits = 0;

  Map<String, ThreadDetailBodyManifest> get bodies => manifests;
  Map<String, ThreadDetailBodyManifest> get manifests =>
      Map.unmodifiable(_manifests);
  ThreadDetailBodyManifest? operator [](String pid) => _manifests[pid];
  int get retainedCodeUnits => _retainedCodeUnits;
  int get cachedChunkCount => _chunks.length;

  bool isCurrent(ThreadDetailBodyManifest manifest) =>
      identical(_manifests[manifest.request.sourceId], manifest);

  bool canAdmit(String pid, ThreadDetailPreparedBody body) =>
      _isSafePreparedBody(pid, body);

  bool admit(String pid, ThreadDetailPreparedBody body, {int seedOrdinal = 0}) {
    if (!canAdmit(pid, body) ||
        !_hasOrdinal(
          body.document.safeDisplayPlan!.chunks.length,
          seedOrdinal,
        )) {
      return false;
    }
    final previous = _manifests[pid];
    if (previous != null && previous.identity == body.request.identity) {
      return rememberPrepared(previous, body, seedOrdinal: seedOrdinal);
    }
    final manifest = ThreadDetailBodyManifest.fromPrepared(body);
    if (previous != null) _removeValues(previous);
    _manifests[pid] = manifest;
    _rememberValidated(manifest, body, seedOrdinal);
    return true;
  }

  ThreadDetailPreparedChunk? chunkFor(
    ThreadDetailBodyManifest manifest,
    int ordinal,
  ) {
    if (!isCurrent(manifest) || !_hasOrdinal(manifest.chunks.length, ordinal)) {
      return null;
    }
    final key = (manifest, ordinal);
    final chunk = _chunks.remove(key);
    if (chunk != null) _chunks[key] = chunk;
    return chunk;
  }

  /// A cache miss may prepare the complete body again. Confirm that its output
  /// still matches the published boundaries before supplying any chunk values.
  bool rememberPrepared(
    ThreadDetailBodyManifest manifest,
    ThreadDetailPreparedBody body, {
    int seedOrdinal = 0,
  }) {
    if (!isCurrent(manifest) ||
        !_hasOrdinal(manifest.chunks.length, seedOrdinal) ||
        !manifest.matches(body)) {
      return false;
    }
    _rememberValidated(manifest, body, seedOrdinal);
    return true;
  }

  void _rememberValidated(
    ThreadDetailBodyManifest manifest,
    ThreadDetailPreparedBody body,
    int seedOrdinal,
  ) {
    final selected = <int>[];
    var available = maxRetainedCodeUnits;
    void select(int ordinal) {
      if (!_hasOrdinal(manifest.chunks.length, ordinal)) return;
      final length = manifest.chunks[ordinal].htmlCodeUnits;
      if (length > available) return;
      selected.add(ordinal);
      available -= length;
    }

    select(seedOrdinal);
    for (var distance = 1; distance < manifest.chunks.length; distance++) {
      select(seedOrdinal - distance);
      select(seedOrdinal + distance);
    }
    // Insert the farthest chosen neighbors first. The demanded block and its
    // nearest neighbors remain hottest even when this displaces another floor.
    for (final ordinal in selected.reversed) {
      final source = body.document.safeDisplayPlan!.chunks[ordinal];
      final key = (manifest, ordinal);
      final previous = _chunks.remove(key);
      if (previous != null) _retainedCodeUnits -= previous.html.length;
      final chunk =
          previous ??
          ThreadDetailPreparedChunk(
            document: body.document.copyWith(
              preparedHtml: source.html,
              clearSafeDisplayPlan: true,
            ),
            ordinal: ordinal,
            hasTrailingContent: source.hasTrailingContent,
          );
      while (_chunks.isNotEmpty &&
          _retainedCodeUnits + chunk.html.length > maxRetainedCodeUnits) {
        final oldest = _chunks.remove(_chunks.keys.first)!;
        _retainedCodeUnits -= oldest.html.length;
      }
      _chunks[key] = chunk;
      _retainedCodeUnits += chunk.html.length;
    }
  }

  /// The host activates its current layout before reading or reporting heights.
  /// A late measurement from an older layout cannot reactivate that layout.
  void activateHeightLayout(
    ThreadDetailBodyManifest manifest, {
    required Object layoutIdentity,
  }) {
    if (!isCurrent(manifest)) return;
    if (_heights[manifest]?.layoutIdentity != layoutIdentity) {
      _heights[manifest] = _ChunkHeightLedger(layoutIdentity);
    }
  }

  void rememberHeight(
    ThreadDetailBodyManifest manifest,
    int ordinal, {
    required Object layoutIdentity,
    required double height,
  }) {
    if (!isCurrent(manifest) ||
        !_hasOrdinal(manifest.chunks.length, ordinal) ||
        !height.isFinite ||
        height < 0) {
      return;
    }
    final ledger = _heights.putIfAbsent(
      manifest,
      () => _ChunkHeightLedger(layoutIdentity),
    );
    if (ledger.layoutIdentity == layoutIdentity) {
      ledger.heights[ordinal] = height;
    }
  }

  double? heightFor(
    ThreadDetailBodyManifest manifest,
    int ordinal, {
    required Object layoutIdentity,
  }) {
    if (!isCurrent(manifest) || !_hasOrdinal(manifest.chunks.length, ordinal)) {
      return null;
    }
    final ledger = _heights[manifest];
    return ledger?.layoutIdentity == layoutIdentity
        ? ledger?.heights[ordinal]
        : null;
  }

  void retainWhere(bool Function(String, ThreadDetailBodyManifest) valid) {
    _manifests.removeWhere((pid, manifest) {
      if (valid(pid, manifest)) return false;
      _removeValues(manifest);
      return true;
    });
  }

  void _removeValues(ThreadDetailBodyManifest manifest) {
    _chunks.removeWhere((key, chunk) {
      if (!identical(key.$1, manifest)) return false;
      _retainedCodeUnits -= chunk.html.length;
      return true;
    });
    _heights.remove(manifest);
  }

  void clear() {
    _manifests.clear();
    _chunks.clear();
    _heights.clear();
    _retainedCodeUnits = 0;
  }
}

final class _ChunkHeightLedger {
  _ChunkHeightLedger(this.layoutIdentity);

  final Object layoutIdentity;
  final heights = <int, double>{};
}

bool _hasOrdinal(int count, int ordinal) => ordinal >= 0 && ordinal < count;

String _htmlFingerprint(String html) =>
    sha256.convert(utf8.encode(html)).toString();

bool _isSafePreparedBody(String pid, ThreadDetailPreparedBody body) {
  final plan = body.document.safeDisplayPlan;
  if (body.request.sourceId != pid ||
      plan == null ||
      !plan.isChunked ||
      plan.chunks.isEmpty ||
      plan.sourceId != pid ||
      plan.sourceHtml != body.document.preparedHtml) {
    return false;
  }
  var endUnit = 0;
  for (var ordinal = 0; ordinal < plan.chunks.length; ordinal++) {
    final chunk = plan.chunks[ordinal];
    if (chunk.ordinal != ordinal ||
        chunk.sourceId != pid ||
        chunk.sourceHtml != plan.sourceHtml ||
        chunk.startUnit != endUnit ||
        chunk.endUnit <= chunk.startUnit ||
        chunk.hasTrailingContent != (ordinal + 1 < plan.chunks.length)) {
      return false;
    }
    endUnit = chunk.endUnit;
  }
  return true;
}
