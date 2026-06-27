import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';

class ThreadPostBodyRenderPlan {
  const ThreadPostBodyRenderPlan({
    required this.document,
    required this.images,
    required this.segments,
    required this.usesListSegments,
  });

  final ThreadPostBodyDocument document;
  final List<ThreadPostImageBlock> images;
  final List<ThreadPostBodySegment> segments;

  /// True when body blocks are split into multiple outer list entries.
  ///
  /// Native thread reading keeps selection out of the scrolling page; a
  /// dedicated copy page renders the full floor body when cross-block selection
  /// is needed.
  final bool usesListSegments;
}

class ThreadPostBodySegment {
  const ThreadPostBodySegment({
    required this.index,
    required this.blocks,
    required this.anchorId,
  });

  final int index;
  final List<ThreadPostBodyBlock> blocks;
  final String anchorId;
}
