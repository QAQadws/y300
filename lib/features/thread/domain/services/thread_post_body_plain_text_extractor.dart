import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';

class ThreadPostBodyPlainTextExtractor {
  const ThreadPostBodyPlainTextExtractor();

  String extract(ThreadPostBodyDocument document) {
    return _extractBlocks(document.blocks).join('\n').trim();
  }

  List<String> _extractBlocks(List<ThreadPostBodyBlock> blocks) {
    final lines = <String>[];
    for (final block in blocks) {
      final blockLines = _extractBlock(block);
      for (final line in blockLines) {
        if (line.trim().isNotEmpty) {
          lines.add(line);
        }
      }
    }
    return lines;
  }

  List<String> _extractBlock(ThreadPostBodyBlock block) {
    if (block is ThreadPostTextBlock) {
      return <String>[_extractTextRuns(block.runs)];
    }
    if (block is ThreadPostQuoteBlock) {
      return _extractBlocks(block.blocks);
    }
    return const <String>[];
  }

  String _extractTextRuns(List<ThreadPostTextRun> runs) {
    final buffer = StringBuffer();
    for (final run in runs) {
      final image = run.inlineImage;
      if (image != null) {
        final altText = image.altText?.trim();
        if (altText != null && altText.isNotEmpty) {
          buffer.write(altText);
        }
        continue;
      }
      buffer.write(run.text);
    }
    return buffer.toString();
  }
}
