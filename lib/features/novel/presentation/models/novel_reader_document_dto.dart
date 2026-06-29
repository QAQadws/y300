import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document_codec.dart';

/// Serializes a [NovelReaderDocument] for isolate transport. The block tree is
/// delegated to the shared [RichDocumentCodec]; only the novel metadata
/// (episode id, hash, plain text, word count) is handled here.
class NovelReaderDocumentDto {
  const NovelReaderDocumentDto({
    required this.episodeId,
    required this.rawHtmlHash,
    required this.body,
    required this.plainText,
    required this.wordCount,
  });

  static const RichDocumentCodec _codec = RichDocumentCodec();

  final String episodeId;
  final String rawHtmlHash;
  final Map<String, Object?> body;
  final String plainText;
  final int wordCount;

  factory NovelReaderDocumentDto.fromDocument(NovelReaderDocument document) {
    return NovelReaderDocumentDto(
      episodeId: document.episodeId,
      rawHtmlHash: document.rawHtmlHash,
      body: _codec.encodeDocument(document.body),
      plainText: document.plainText,
      wordCount: document.wordCount,
    );
  }

  factory NovelReaderDocumentDto.fromMap(Map<String, Object?> map) {
    return NovelReaderDocumentDto(
      episodeId: map['episodeId'] as String? ?? '',
      rawHtmlHash: map['rawHtmlHash'] as String? ?? '',
      body: _castMap(map['body']),
      plainText: map['plainText'] as String? ?? '',
      wordCount: map['wordCount'] as int? ?? 0,
    );
  }

  NovelReaderDocument toDocument() {
    return NovelReaderDocument(
      episodeId: episodeId,
      rawHtmlHash: rawHtmlHash,
      body: _codec.decodeDocument(body),
      plainText: plainText,
      wordCount: wordCount,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'episodeId': episodeId,
      'rawHtmlHash': rawHtmlHash,
      'body': body,
      'plainText': plainText,
      'wordCount': wordCount,
    };
  }
}

Map<String, Object?> _castMap(Object? raw) {
  if (raw is Map<Object?, Object?>) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, Object?>{};
}
