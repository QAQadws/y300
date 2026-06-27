import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_anchor.dart';

class ThreadPostBodyDocumentNormalizer {
  const ThreadPostBodyDocumentNormalizer({this.maxTextRunLength = 320})
    : assert(maxTextRunLength > 0);

  final int maxTextRunLength;

  ThreadPostBodyDocument normalize(ThreadPostBodyDocument document) {
    return ThreadPostBodyDocument(blocks: _normalizeBlocks(document.blocks));
  }

  List<ThreadPostBodyBlock> _normalizeBlocks(List<ThreadPostBodyBlock> blocks) {
    final output = <ThreadPostBodyBlock>[];
    for (final block in blocks) {
      final normalized = _normalizeBlock(block);
      for (final item in normalized) {
        if (_isEmptyTextBlock(item)) {
          continue;
        }
        output.add(item);
      }
    }
    return List<ThreadPostBodyBlock>.unmodifiable(output);
  }

  List<ThreadPostBodyBlock> _normalizeBlock(ThreadPostBodyBlock block) {
    if (block is ThreadPostTextBlock) {
      final runs = _mergeAdjacentRuns(block.runs)
          .where((run) => run.inlineImage != null || run.text.trim().isNotEmpty)
          .toList(growable: false);
      if (runs.isEmpty) {
        return const <ThreadPostBodyBlock>[];
      }
      return _splitTextBlock(block, runs);
    }
    if (block is ThreadPostQuoteBlock) {
      final children = _normalizeBlocks(block.blocks);
      if (children.isEmpty) {
        return const <ThreadPostBodyBlock>[];
      }
      return <ThreadPostBodyBlock>[
        ThreadPostQuoteBlock(
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
    return <ThreadPostBodyBlock>[block];
  }

  List<ThreadPostBodyBlock> _splitTextBlock(
    ThreadPostTextBlock block,
    List<ThreadPostTextRun> runs,
  ) {
    final result = <ThreadPostTextBlock>[];
    var currentRuns = <ThreadPostTextRun>[];
    var currentLength = 0;
    var segmentIndex = 0;

    void flush() {
      if (currentRuns.isEmpty) {
        return;
      }
      result.add(
        ThreadPostTextBlock(
          anchorId: _segmentAnchorId(block, segmentIndex, currentRuns),
          continuesPrevious: block.continuesPrevious || segmentIndex > 0,
          runs: List<ThreadPostTextRun>.unmodifiable(currentRuns),
        ),
      );
      segmentIndex += 1;
      currentRuns = <ThreadPostTextRun>[];
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
    return List<ThreadPostBodyBlock>.unmodifiable(result);
  }

  String _segmentAnchorId(
    ThreadPostTextBlock block,
    int segmentIndex,
    List<ThreadPostTextRun> runs,
  ) {
    final prefix = block.anchorId.isEmpty ? 'text' : block.anchorId;
    return threadPostBodyAnchorId(
      'text',
      '$prefix|$segmentIndex|${runs.map(_anchorSeedForRun).join('|')}',
    );
  }

  List<ThreadPostTextRun> _mergeAdjacentRuns(List<ThreadPostTextRun> runs) {
    final output = <ThreadPostTextRun>[];
    for (final run in runs) {
      if (output.isNotEmpty && _sameTextStyle(output.last, run)) {
        final previous = output.removeLast();
        output.add(_copyRun(previous, '${previous.text}${run.text}'));
      } else {
        output.add(run);
      }
    }
    return List<ThreadPostTextRun>.unmodifiable(output);
  }

  bool _sameTextStyle(ThreadPostTextRun a, ThreadPostTextRun b) {
    return a.inlineImage == null &&
        b.inlineImage == null &&
        a.linkUrl == b.linkUrl &&
        a.isBold == b.isBold &&
        a.isItalic == b.isItalic &&
        a.isUnderline == b.isUnderline;
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

  bool _isEmptyTextBlock(ThreadPostBodyBlock block) {
    return block is ThreadPostTextBlock &&
        block.runs.every(
          (run) => run.inlineImage == null && run.text.trim().isEmpty,
        );
  }

  String _anchorSeedForRun(ThreadPostTextRun run) {
    final image = run.inlineImage;
    return image == null
        ? '${run.text}|${run.linkUrl}|${run.isBold}|${run.isItalic}|${run.isUnderline}'
        : 'image:${image.url}|${run.linkUrl}|${run.isBold}|${run.isItalic}|${run.isUnderline}';
  }
}
