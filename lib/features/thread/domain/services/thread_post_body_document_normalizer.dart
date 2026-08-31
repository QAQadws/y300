import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_anchor.dart';

class ThreadPostBodyDocumentNormalizer {
  const ThreadPostBodyDocumentNormalizer({this.maxTextRunLength = 320})
    : assert(maxTextRunLength > 0);

  final int maxTextRunLength;

  RichDocument normalize(RichDocument document) {
    return RichDocument(blocks: _normalizeBlocks(document.blocks));
  }

  List<RichBlock> _normalizeBlocks(List<RichBlock> blocks) {
    final output = <RichBlock>[];
    for (final block in blocks) {
      final normalized = _normalizeBlock(block);
      for (final item in normalized) {
        if (_isEmptyTextBlock(item)) {
          continue;
        }
        output.add(item);
      }
    }
    return List<RichBlock>.unmodifiable(output);
  }

  List<RichBlock> _normalizeBlock(RichBlock block) {
    if (block is RichTextBlock) {
      final runs = _mergeAdjacentRuns(block.runs)
          .where((run) => run.inlineImage != null || run.text.trim().isNotEmpty)
          .toList(growable: false);
      if (runs.isEmpty) {
        return const <RichBlock>[];
      }
      return _splitTextBlock(block, runs);
    }
    if (block is RichQuoteBlock) {
      final children = _normalizeBlocks(block.blocks);
      if (children.isEmpty) {
        return const <RichBlock>[];
      }
      return <RichBlock>[
        RichQuoteBlock(
          anchorId: block.anchorId.isEmpty
              ? threadPostBodyAnchorId(
                  'quote',
                  children.map((child) => child.anchorId).join('|'),
                )
              : block.anchorId,
          continuesPrevious: block.continuesPrevious,
          blocks: children,
        ),
      ];
    }
    return <RichBlock>[block];
  }

  List<RichBlock> _splitTextBlock(RichTextBlock block, List<RichRun> runs) {
    final result = <RichTextBlock>[];
    var currentRuns = <RichRun>[];
    var currentLength = 0;
    var segmentIndex = 0;

    void flush() {
      if (currentRuns.isEmpty) {
        return;
      }
      result.add(
        RichTextBlock(
          anchorId: _segmentAnchorId(block, segmentIndex, currentRuns),
          continuesPrevious: block.continuesPrevious || segmentIndex > 0,
          runs: List<RichRun>.unmodifiable(currentRuns),
        ),
      );
      segmentIndex += 1;
      currentRuns = <RichRun>[];
      currentLength = 0;
    }

    for (final run in runs) {
      if (run.inlineImage != null) {
        if (currentLength >= maxTextRunLength) {
          flush();
        }
        currentRuns.add(run);
        currentLength += 1;
        continue;
      }

      final text = run.text;
      var offset = 0;
      while (offset < text.length) {
        final remaining = text.length - offset;
        final available = maxTextRunLength - currentLength;
        final take = available <= 0
            ? 0
            : (remaining < available ? remaining : available);
        if (take == 0) {
          flush();
          continue;
        }
        currentRuns.add(_copyRun(run, text.substring(offset, offset + take)));
        currentLength += take;
        offset += take;
        if (currentLength >= maxTextRunLength && offset < text.length) {
          flush();
        }
      }
    }
    flush();
    return List<RichBlock>.unmodifiable(result);
  }

  String _segmentAnchorId(
    RichTextBlock block,
    int segmentIndex,
    List<RichRun> runs,
  ) {
    final prefix = block.anchorId.isEmpty ? 'text' : block.anchorId;
    return threadPostBodyAnchorId(
      'text',
      '$prefix|$segmentIndex|${runs.map(_anchorSeedForRun).join('|')}',
    );
  }

  List<RichRun> _mergeAdjacentRuns(List<RichRun> runs) {
    final output = <RichRun>[];
    for (final run in runs) {
      if (output.isNotEmpty && _sameTextStyle(output.last, run)) {
        final previous = output.removeLast();
        output.add(_copyRun(previous, '${previous.text}${run.text}'));
      } else {
        output.add(run);
      }
    }
    return List<RichRun>.unmodifiable(output);
  }

  bool _sameTextStyle(RichRun a, RichRun b) {
    return a.inlineImage == null &&
        b.inlineImage == null &&
        a.linkUrl == b.linkUrl &&
        a.isBold == b.isBold &&
        a.isItalic == b.isItalic &&
        a.isUnderline == b.isUnderline;
  }

  RichRun _copyRun(RichRun source, String text) {
    return RichRun(
      text: text,
      linkUrl: source.linkUrl,
      isBold: source.isBold,
      isItalic: source.isItalic,
      isUnderline: source.isUnderline,
      inlineImage: source.inlineImage,
    );
  }

  bool _isEmptyTextBlock(RichBlock block) {
    return block is RichTextBlock &&
        block.runs.every(
          (run) => run.inlineImage == null && run.text.trim().isEmpty,
        );
  }

  String _anchorSeedForRun(RichRun run) {
    final image = run.inlineImage;
    return image == null
        ? '${run.text}|${run.linkUrl}|${run.isBold}|${run.isItalic}|${run.isUnderline}'
        : 'image:${image.url}|${run.linkUrl}|${run.isBold}|${run.isItalic}|${run.isUnderline}';
  }
}
