import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_layout_key.dart';

class NovelReaderLayoutRequest {
  const NovelReaderLayoutRequest({
    required this.episodeId,
    required this.rawHtmlHash,
    required this.document,
    required this.viewport,
    required this.metrics,
    required this.pagePadding,
    required this.contentMaxWidth,
    required this.fontWeight,
    required this.fontFamily,
    required this.textAlign,
    required this.firstLineIndent,
  });

  final String episodeId;
  final String rawHtmlHash;
  final NovelReaderDocument document;
  final NovelReaderViewport viewport;
  final NovelReaderPaginationMetrics metrics;
  final double pagePadding;
  final double contentMaxWidth;
  final int fontWeight;
  final String fontFamily;
  final String textAlign;
  final double firstLineIndent;

  NovelReaderLayoutKey get key {
    return NovelReaderLayoutKey(
      episodeId: episodeId,
      rawHtmlHash: rawHtmlHash,
      viewportWidthPx: viewport.width.round(),
      viewportHeightPx: viewport.height.round(),
      bodyFontSizeX10: (metrics.bodyFontSize * 10).round(),
      bodyLineHeightX100: (metrics.bodyLineHeight * 100).round(),
      headingFontSizeX10: (metrics.headingFontSize * 10).round(),
      headingLineHeightX100: (metrics.headingLineHeight * 100).round(),
      paragraphSpacingX10: (metrics.paragraphSpacing * 10).round(),
      pagePaddingX10: (pagePadding * 10).round(),
      contentMaxWidthX10: (contentMaxWidth * 10).round(),
      fontWeight: fontWeight,
      fontFamily: fontFamily,
      textAlign: textAlign,
      firstLineIndentX10: (firstLineIndent * 10).round(),
    );
  }
}
