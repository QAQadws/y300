import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_anchor.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_document_normalizer.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_parser.dart';
import 'package:y300/features/thread/domain/services/thread_post_resource_layout_hint_resolver.dart';

class ThreadPostBodyRenderPlanner {
  const ThreadPostBodyRenderPlanner({
    this.parser = const ThreadPostBodyParser(),
    this.normalizer = const ThreadPostBodyDocumentNormalizer(
      maxTextRunLength: 600,
    ),
    this.resourceLayoutHintResolver =
        const ThreadPostResourceLayoutHintResolver(),
    this.maxSegmentTextLength = 600,
  }) : assert(maxSegmentTextLength > 0);

  final ThreadPostBodyParser parser;
  final ThreadPostBodyDocumentNormalizer normalizer;
  final ThreadPostResourceLayoutHintResolver resourceLayoutHintResolver;
  final int maxSegmentTextLength;

  String get resourceHintResolverSignature =>
      resourceLayoutHintResolver.signature;

  ThreadPostBodyRenderPlan plan(
    String html, {
    ThreadPostBodyRenderSettings renderSettings =
        ThreadPostBodyRenderSettings.defaults,
  }) {
    final document = normalizer.normalize(parser.parse(html));
    return planDocument(document, renderSettings: renderSettings);
  }

  ThreadPostBodyRenderPlan planDocument(
    ThreadPostBodyDocument document, {
    ThreadPostBodyRenderSettings renderSettings =
        ThreadPostBodyRenderSettings.defaults,
  }) {
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

    for (final sourceBlock in document.blocks) {
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

    return ThreadPostBodyRenderPlan(
      document: document,
      images: document.images,
      segments: List<ThreadPostBodySegment>.unmodifiable(segments),
      usesListSegments: segments.length > 1,
      renderSettingsSignature: renderSettings.signature,
      resourceHintResolverSignature: resourceHintResolverSignature,
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
