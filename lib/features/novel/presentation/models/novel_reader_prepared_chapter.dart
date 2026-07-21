import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_legacy_markup_normalization.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';

/// A visual chapter prepared by the HTML-first renderer.
///
/// The prepared HTML and [renderDocument] are the same inputs consumed by the
/// vertical renderer. [flowUnits] is a structural view over that prepared
/// document for the future paged layout; it does not introduce another HTML
/// parser or another image sequence.
class NovelReaderPreparedChapter {
  const NovelReaderPreparedChapter({
    required this.episodeId,
    required this.contentHash,
    required this.html,
    required this.renderDocument,
    required this.flowUnits,
    required this.themeSignature,
    required this.imageDimensionRevision,
    required this.convertedTextNodeCount,
    this.legacyMarkupNormalization =
        NovelReaderLegacyMarkupNormalizationSummary.none,
  });

  final String episodeId;
  final String contentHash;
  final String html;
  final ForumHtmlPreparedRenderDocument renderDocument;
  final List<NovelReaderFlowUnit> flowUnits;
  final String themeSignature;
  final int imageDimensionRevision;
  final int convertedTextNodeCount;
  final NovelReaderLegacyMarkupNormalizationSummary legacyMarkupNormalization;
}

class NovelReaderFlowUnit {
  const NovelReaderFlowUnit({
    required this.unitId,
    required this.html,
    required this.startAnchor,
    required this.endAnchor,
    required this.breakability,
    required this.imageIndices,
  });

  final String unitId;
  final String html;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;
  final NovelReaderFlowUnitBreakability breakability;
  final List<int> imageIndices;
}

enum NovelReaderFlowUnitBreakability {
  text,
  inlineText,
  blockImage,
  atomicWidget,
}
