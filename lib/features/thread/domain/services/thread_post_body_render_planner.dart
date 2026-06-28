import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/models/thread_post_render_cache_key.dart';
import 'package:y300/features/thread/domain/models/thread_post_segmentation_config.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_anchor.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_display_transformer.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_document_normalizer.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_parser.dart';
import 'package:y300/features/thread/domain/services/thread_post_resource_layout_hint_resolver.dart';

class ThreadPostBodyRenderPlanner {
  const ThreadPostBodyRenderPlanner({
    this.parser = const ThreadPostBodyParser(),
    this.normalizer,
    this.resourceLayoutHintResolver =
        const ThreadPostResourceLayoutHintResolver(),
    this.displayTransformer = const ThreadPostBodyDisplayTransformer(),
    this.segmentation = ThreadPostSegmentationConfig.standard,
    // Kept for explicit overrides in tests; prefer [segmentation].
    int? maxSegmentTextLength,
  }) : _maxSegmentTextLength = maxSegmentTextLength,
       assert(maxSegmentTextLength == null || maxSegmentTextLength > 0);

  final ThreadPostBodyParser parser;
  final ThreadPostBodyDocumentNormalizer? normalizer;
  final ThreadPostResourceLayoutHintResolver resourceLayoutHintResolver;
  final ThreadPostBodyDisplayTransformer displayTransformer;
  final ThreadPostSegmentationConfig segmentation;
  final int? _maxSegmentTextLength;

  /// Effective segment text length — explicit override wins over [segmentation].
  int get maxSegmentTextLength =>
      _maxSegmentTextLength ?? segmentation.maxSegmentTextLength;

  /// The normalizer to use; defaults to a normalizer aligned with [segmentation].
  ThreadPostBodyDocumentNormalizer get _normalizer =>
      normalizer ??
      ThreadPostBodyDocumentNormalizer(
        maxTextRunLength: maxSegmentTextLength,
      );

  String get resourceHintResolverSignature =>
      resourceLayoutHintResolver.signature;

  String get displayTransformerSignature => displayTransformer.signature;

  ThreadPostBodyRenderPlan plan(
    String html, {
    ThreadPostBodyRenderSettings renderSettings =
        ThreadPostBodyRenderSettings.defaults,
    String converterId = 'conv:none',
    RichTextTypography typography = RichTextTypography.standard,
  }) {
    final document = _normalizer.normalize(parser.parse(html));
    return planDocument(
      document,
      renderSettings: renderSettings,
      converterId: converterId,
      typography: typography,
    );
  }

  ThreadPostBodyRenderPlan planDocument(
    ThreadPostBodyDocument document, {
    ThreadPostBodyRenderSettings renderSettings =
        ThreadPostBodyRenderSettings.defaults,
    String converterId = 'conv:none',
    RichTextTypography typography = RichTextTypography.standard,
  }) {
    final displayDocument = displayTransformer.transform(document);
    final segments = <ThreadPostBodySegment>[];
    var pendingBlocks = <ThreadPostBodyBlock>[];
    var pendingTextLength = 0;
    var segmentIndex = 0;

    void flushPending() {
      if (pendingBlocks.isEmpty) {
        return;
      }
      segments.add(
        ThreadPostBodySegment(
          index: segmentIndex,
          blocks: List<ThreadPostBodyBlock>.unmodifiable(pendingBlocks),
          anchorId: _segmentAnchorId(segmentIndex, pendingBlocks),
        ),
      );
      segmentIndex += 1;
      pendingBlocks = <ThreadPostBodyBlock>[];
      pendingTextLength = 0;
    }

    for (final sourceBlock in displayDocument.blocks) {
      for (final block in _segmentableBlocks(sourceBlock)) {
        if (block is ThreadPostImageBlock) {
          flushPending();
          segments.add(
            ThreadPostBodySegment(
              index: segmentIndex,
              blocks: <ThreadPostBodyBlock>[block],
              anchorId: _segmentAnchorId(segmentIndex, <ThreadPostBodyBlock>[
                block,
              ]),
            ),
          );
          segmentIndex += 1;
          continue;
        }

        final blockWeight = _blockTextWeight(block);
        if (pendingBlocks.isNotEmpty &&
            pendingTextLength > 0 &&
            pendingTextLength + blockWeight > maxSegmentTextLength) {
          flushPending();
        }
        pendingBlocks.add(block);
        pendingTextLength += blockWeight;
      }
    }
    flushPending();

    final renderKey = ThreadPostRenderCacheKey(
      renderSettings: renderSettings,
      displayTransformerSignature: displayTransformerSignature,
      resourceHintResolverSignature: resourceHintResolverSignature,
      segmentation: segmentation,
      converterId: converterId,
      typography: typography,
    );

    return ThreadPostBodyRenderPlan(
      document: document,
      displayDocument: displayDocument,
      images: displayDocument.images,
      segments: List<ThreadPostBodySegment>.unmodifiable(segments),
      usesListSegments: segments.length > 1,
      renderKey: renderKey,
      resourceLayoutHints: resourceLayoutHintResolver.resolve(document),
    );
  }

  Iterable<ThreadPostBodyBlock> _segmentableBlocks(
    ThreadPostBodyBlock block,
  ) sync* {
    if (block is ThreadPostTextBlock &&
        _blockTextWeight(block) > maxSegmentTextLength) {
      yield* _splitTextBlock(block);
      return;
    }
    yield block;
  }

  List<ThreadPostTextBlock> _splitTextBlock(ThreadPostTextBlock block) {
    final result = <ThreadPostTextBlock>[];
    var currentRuns = <ThreadPostTextRun>[];
    var currentLength = 0;
    var splitIndex = 0;

    void flush() {
      if (currentRuns.isEmpty) {
        return;
      }
      result.add(
        ThreadPostTextBlock(
          anchorId: threadPostBodyAnchorId(
            'segment-text',
            '${block.anchorId}|$splitIndex|${currentRuns.map(_runAnchorSeed).join('|')}',
          ),
          continuesPrevious: block.continuesPrevious || splitIndex > 0,
          runs: List<ThreadPostTextRun>.unmodifiable(currentRuns),
        ),
      );
      splitIndex += 1;
      currentRuns = <ThreadPostTextRun>[];
      currentLength = 0;
    }

    for (final run in block.runs) {
      if (run.inlineImage != null) {
        if (currentLength >= maxSegmentTextLength) {
          flush();
        }
        currentRuns.add(run);
        currentLength += 1;
        continue;
      }

      final text = run.text;
      var offset = 0;
      while (offset < text.length) {
        final available = maxSegmentTextLength - currentLength;
        if (available <= 0) {
          flush();
          continue;
        }
        final remaining = text.length - offset;
        final take = remaining < available ? remaining : available;
        currentRuns.add(_copyRun(run, text.substring(offset, offset + take)));
        currentLength += take;
        offset += take;
        if (currentLength >= maxSegmentTextLength && offset < text.length) {
          flush();
        }
      }
    }
    flush();
    return List<ThreadPostTextBlock>.unmodifiable(result);
  }

  ThreadPostTextRun _copyRun(ThreadPostTextRun source, String text) {
    return ThreadPostTextRun(
      text: text,
      linkUrl: source.linkUrl,
      isBold: source.isBold,
      isItalic: source.isItalic,
      isUnderline: source.isUnderline,
      inlineImage: source.inlineImage,
    );
  }

  String _runAnchorSeed(ThreadPostTextRun run) {
    final image = run.inlineImage;
    if (image != null) {
      return 'image:${image.url}|${run.linkUrl}|${run.isBold}|${run.isItalic}|${run.isUnderline}';
    }
    return '${run.text}|${run.linkUrl}|${run.isBold}|${run.isItalic}|${run.isUnderline}';
  }

  int _blockTextWeight(ThreadPostBodyBlock block) {
    if (block is ThreadPostTextBlock) {
      return block.runs.fold<int>(0, (total, run) {
        return total + (run.inlineImage == null ? run.text.length : 1);
      });
    }
    if (block is ThreadPostQuoteBlock) {
      return block.blocks.fold<int>(
        0,
        (total, child) => total + _blockTextWeight(child),
      );
    }
    return 0;
  }

  String _segmentAnchorId(int index, List<ThreadPostBodyBlock> blocks) {
    final seed = blocks
        .map((block) => block.anchorId)
        .where((id) => id.trim().isNotEmpty)
        .join('|');
    return threadPostBodyAnchorId('segment', '$index|$seed');
  }
}

