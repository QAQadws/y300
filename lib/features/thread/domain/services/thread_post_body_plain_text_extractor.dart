import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';

enum ThreadPostBlockImageTextPolicy { omit, placeholder, url }

enum ThreadPostInlineImageTextPolicy {
  omit,
  preferBbCode,
  preferAltOrTitle,
  url,
}

enum ThreadPostQuoteTextPolicy { keepTextWithBlankLines, prefixLines }

class ThreadPostPlainTextExtractOptions {
  const ThreadPostPlainTextExtractOptions({
    this.blockImagePolicy = ThreadPostBlockImageTextPolicy.omit,
    this.inlineImagePolicy = ThreadPostInlineImageTextPolicy.preferBbCode,
    this.quotePolicy = ThreadPostQuoteTextPolicy.keepTextWithBlankLines,
    this.blockImagePlaceholder = '[图片]',
    this.quoteLinePrefix = '> ',
  });

  static const defaults = ThreadPostPlainTextExtractOptions();

  final ThreadPostBlockImageTextPolicy blockImagePolicy;
  final ThreadPostInlineImageTextPolicy inlineImagePolicy;
  final ThreadPostQuoteTextPolicy quotePolicy;
  final String blockImagePlaceholder;
  final String quoteLinePrefix;
}

class ThreadPostBodyPlainTextExtractor {
  const ThreadPostBodyPlainTextExtractor({
    this.options = ThreadPostPlainTextExtractOptions.defaults,
  });

  final ThreadPostPlainTextExtractOptions options;

  String extract(
    RichDocument document, {
    ThreadPostPlainTextExtractOptions? options,
  }) {
    final resolvedOptions = options ?? this.options;
    return _extractBlocks(document.blocks, resolvedOptions).join('\n').trim();
  }

  List<String> _extractBlocks(
    List<RichBlock> blocks,
    ThreadPostPlainTextExtractOptions options,
  ) {
    final lines = <String>[];
    for (final block in blocks) {
      final blockLines = _extractBlock(block, options);
      for (final line in blockLines) {
        if (line.trim().isEmpty) {
          if (lines.isNotEmpty && lines.last.isNotEmpty) {
            lines.add('');
          }
          continue;
        }
        lines.add(line);
      }
    }
    return lines;
  }

  List<String> _extractBlock(
    RichBlock block,
    ThreadPostPlainTextExtractOptions options,
  ) {
    if (block is RichTextBlock) {
      final text = _extractTextRuns(block.runs, options);
      return text.trim().isEmpty ? const <String>[] : <String>[text];
    }
    if (block is RichQuoteBlock) {
      final lines = _extractBlocks(block.blocks, options);
      return switch (options.quotePolicy) {
        ThreadPostQuoteTextPolicy.keepTextWithBlankLines =>
          lines.isEmpty ? const <String>[] : <String>['', ...lines, ''],
        ThreadPostQuoteTextPolicy.prefixLines =>
          lines
              .map((line) => '${options.quoteLinePrefix}$line')
              .toList(growable: false),
      };
    }
    if (block is RichImageBlock) {
      return switch (options.blockImagePolicy) {
        ThreadPostBlockImageTextPolicy.omit => const <String>[],
        ThreadPostBlockImageTextPolicy.placeholder => <String>[
          options.blockImagePlaceholder,
        ],
        ThreadPostBlockImageTextPolicy.url => <String>[block.url],
      };
    }
    return const <String>[];
  }

  String _extractTextRuns(
    List<RichRun> runs,
    ThreadPostPlainTextExtractOptions options,
  ) {
    final buffer = StringBuffer();
    for (final run in runs) {
      final image = run.inlineImage;
      if (image != null) {
        buffer.write(_inlineImageText(image, options));
        continue;
      }
      final text = run.text;
      if (text.isNotEmpty) {
        buffer.write(text);
        continue;
      }
      final linkUrl = run.linkUrl?.trim();
      if (linkUrl != null && linkUrl.isNotEmpty) {
        buffer.write(linkUrl);
      }
    }
    return buffer.toString();
  }

  String _inlineImageText(
    RichInlineImage image,
    ThreadPostPlainTextExtractOptions options,
  ) {
    return switch (options.inlineImagePolicy) {
      ThreadPostInlineImageTextPolicy.omit => '',
      ThreadPostInlineImageTextPolicy.url => image.url,
      ThreadPostInlineImageTextPolicy.preferAltOrTitle => _firstNonEmpty(
        <String?>[image.altText, image.titleText],
      ),
      ThreadPostInlineImageTextPolicy.preferBbCode => _firstNonEmpty(<String?>[
        _bbCodeFromAlt(image.altText),
        _bbCodeFromAlt(image.titleText),
        image.altText,
        image.titleText,
      ]),
    };
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String? _bbCodeFromAlt(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    if (text.startsWith('[') && text.endsWith(']')) {
      return text;
    }
    return null;
  }
}
