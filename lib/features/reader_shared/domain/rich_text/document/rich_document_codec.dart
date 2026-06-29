import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';

/// Serializes and deserializes [RichDocument] to/from plain Dart maps for
/// isolate message passing (see novel reader's IsolateNovelReaderDocumentBuildExecutor).
///
/// The codec is intentionally flat and runtime-only; no JSON files are written.
/// Parsing/conversion always runs on demand when opening a chapter.
class RichDocumentCodec {
  const RichDocumentCodec();

  Map<String, Object?> encodeDocument(RichDocument document) {
    return <String, Object?>{
      'blocks': document.blocks.map(encodeBlock).toList(growable: false),
    };
  }

  RichDocument decodeDocument(Map<String, Object?> map) {
    final rawBlocks = map['blocks'] as List<Object?>? ?? const <Object?>[];
    final blocks = rawBlocks
        .map((item) => decodeBlock(_castMap(item)))
        .toList(growable: false);
    return RichDocument(blocks: blocks);
  }

  Map<String, Object?> encodeBlock(RichBlock block) {
    final baseFields = <String, Object?>{
      'anchorId': block.anchorId,
      'continuesPrevious': block.continuesPrevious,
    };
    return switch (block) {
      RichTextBlock() => <String, Object?>{
          ...baseFields,
          'type': 'text',
          'runs': block.runs.map(encodeRun).toList(growable: false),
          'headingLevel': block.headingLevel,
        },
      RichQuoteBlock() => <String, Object?>{
          ...baseFields,
          'type': 'quote',
          'blocks': block.blocks.map(encodeBlock).toList(growable: false),
        },
      RichImageBlock() => <String, Object?>{
          ...baseFields,
          'type': 'image',
          'url': block.url,
          'rawUrl': block.rawUrl,
          'index': block.index,
          'aid': block.aid,
          'altText': block.altText,
          'originalWidth': block.originalWidth,
          'originalHeight': block.originalHeight,
        },
      RichDividerBlock() => <String, Object?>{
          ...baseFields,
          'type': 'divider',
        },
      RichSpacerBlock() => <String, Object?>{
          ...baseFields,
          'type': 'spacer',
        },
    };
  }

  RichBlock decodeBlock(Map<String, Object?> map) {
    final type = map['type'] as String? ?? 'text';
    final anchorId = map['anchorId'] as String? ?? '';
    final continuesPrevious = map['continuesPrevious'] as bool? ?? false;

    return switch (type) {
      'text' => RichTextBlock(
          anchorId: anchorId,
          continuesPrevious: continuesPrevious,
          runs: _decodeRuns(map['runs']),
          headingLevel: map['headingLevel'] as int? ?? 0,
        ),
      'quote' => RichQuoteBlock(
          anchorId: anchorId,
          continuesPrevious: continuesPrevious,
          blocks: _decodeBlocks(map['blocks']),
        ),
      'image' => RichImageBlock(
          anchorId: anchorId,
          continuesPrevious: continuesPrevious,
          url: map['url'] as String? ?? '',
          rawUrl: map['rawUrl'] as String? ?? '',
          index: map['index'] as int? ?? 0,
          aid: map['aid'] as String?,
          altText: map['altText'] as String?,
          originalWidth: map['originalWidth'] as double?,
          originalHeight: map['originalHeight'] as double?,
        ),
      'divider' => RichDividerBlock(
          anchorId: anchorId,
          continuesPrevious: continuesPrevious,
        ),
      'spacer' => RichSpacerBlock(
          anchorId: anchorId,
          continuesPrevious: continuesPrevious,
        ),
      _ => RichTextBlock(
          anchorId: anchorId,
          continuesPrevious: continuesPrevious,
          runs: const <RichRun>[],
        ),
    };
  }

  Map<String, Object?> encodeRun(RichRun run) {
    return <String, Object?>{
      'text': run.text,
      'linkUrl': run.linkUrl,
      'linkTid': run.linkTid,
      'isBold': run.isBold,
      'isItalic': run.isItalic,
      'isUnderline': run.isUnderline,
      'color': run.color,
      'inlineImage':
          run.inlineImage == null ? null : encodeInlineImage(run.inlineImage!),
    };
  }

  RichRun decodeRun(Map<String, Object?> map) {
    return RichRun(
      text: map['text'] as String? ?? '',
      linkUrl: map['linkUrl'] as String?,
      linkTid: map['linkTid'] as String?,
      isBold: map['isBold'] as bool? ?? false,
      isItalic: map['isItalic'] as bool? ?? false,
      isUnderline: map['isUnderline'] as bool? ?? false,
      color: map['color'] as String?,
      inlineImage: _mapValue(map['inlineImage']) == null
          ? null
          : decodeInlineImage(_mapValue(map['inlineImage'])!),
    );
  }

  Map<String, Object?> encodeInlineImage(RichInlineImage image) {
    return <String, Object?>{
      'url': image.url,
      'rawUrl': image.rawUrl,
      'aid': image.aid,
      'altText': image.altText,
      'titleText': image.titleText,
      'originalWidth': image.originalWidth,
      'originalHeight': image.originalHeight,
    };
  }

  RichInlineImage decodeInlineImage(Map<String, Object?> map) {
    return RichInlineImage(
      url: map['url'] as String? ?? '',
      rawUrl: map['rawUrl'] as String? ?? '',
      aid: map['aid'] as String?,
      altText: map['altText'] as String?,
      titleText: map['titleText'] as String?,
      originalWidth: map['originalWidth'] as double?,
      originalHeight: map['originalHeight'] as double?,
    );
  }

  List<RichBlock> _decodeBlocks(Object? value) {
    if (value is! List<Object?>) {
      return const <RichBlock>[];
    }
    return value.map((item) => decodeBlock(_castMap(item))).toList(growable: false);
  }

  List<RichRun> _decodeRuns(Object? value) {
    if (value is! List<Object?>) {
      return const <RichRun>[];
    }
    return value.map((item) => decodeRun(_castMap(item))).toList(growable: false);
  }

  Map<String, Object?> _castMap(Object? raw) {
    if (raw is Map<Object?, Object?>) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return <String, Object?>{};
  }

  Map<String, Object?>? _mapValue(Object? value) {
    if (value is Map<Object?, Object?>) {
      return _castMap(value);
    }
    return null;
  }
}
