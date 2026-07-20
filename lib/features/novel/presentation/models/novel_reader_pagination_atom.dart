import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';

enum NovelReaderPaginationAtomKind {
  text,
  heading,
  quote,
  image,
  inlineImage,
  atomicWidget,
  spacer,
}

enum NovelReaderImagePagePolicy { isolated, inline }

enum NovelReaderPageGapReason {
  none,
  naturalEnd,
  isolatedImage,
  atomicWidget,
  oversizedWidget,
  chromeInset,
  unknownImageDimension,
  algorithmBoundary,
}

@immutable
class NovelReaderPaginationAtom {
  NovelReaderPaginationAtom({
    required this.atomId,
    required this.kind,
    required this.html,
    required this.startAnchor,
    required this.endAnchor,
    required this.textLength,
    required List<int> imageIndices,
    required this.breakability,
    required this.imagePagePolicy,
  }) : imageIndices = List<int>.unmodifiable(imageIndices);

  final String atomId;
  final NovelReaderPaginationAtomKind kind;
  final String html;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;
  final int textLength;
  final List<int> imageIndices;
  final NovelReaderFlowUnitBreakability breakability;
  final NovelReaderImagePagePolicy imagePagePolicy;

  bool get isIsolatedImage =>
      imagePagePolicy == NovelReaderImagePagePolicy.isolated;
}
