import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_render_cache_key.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';

class ThreadPostBodyRenderPlan {
  const ThreadPostBodyRenderPlan({
    required this.document,
    required this.displayDocument,
    required this.images,
    required this.segments,
    required this.usesListSegments,
    required this.renderKey,
    this.resourceLayoutHints = ThreadPostResourceLayoutHints.empty,
  });

  final RichDocument document;
  final RichDocument displayDocument;
  final List<RichImageBlock> images;
  final List<ThreadPostBodySegment> segments;

  /// True when body blocks are split into multiple outer list entries.
  ///
  /// Native thread reading keeps selection out of the scrolling page; a
  /// dedicated copy page renders the full floor body when cross-block selection
  /// is needed.
  final bool usesListSegments;

  /// Value-object key that captures all render-affecting configuration.
  /// Use for cache invalidation instead of individual signature strings.
  final ThreadPostRenderCacheKey renderKey;

  final ThreadPostResourceLayoutHints resourceLayoutHints;

  // ── Backward-compat accessors (kept while tests migrate) ──────────────────

  String get renderSettingsSignature => renderKey.renderSettings.signature;
  String get displayTransformerSignature =>
      renderKey.displayTransformerSignature;
  String get resourceHintResolverSignature =>
      renderKey.resourceHintResolverSignature;
  String get resourceHintSignature => resourceLayoutHints.signature;
}

class ThreadPostBodySegment {
  const ThreadPostBodySegment({
    required this.index,
    required this.blocks,
    required this.anchorId,
  });

  final int index;
  final List<RichBlock> blocks;
  final String anchorId;
}
