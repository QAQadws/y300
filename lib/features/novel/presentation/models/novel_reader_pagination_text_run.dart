import 'package:flutter/material.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

final class NovelReaderPaginationTextRun {
  const NovelReaderPaginationTextRun({
    required this.text,
    required this.style,
    required this.startAnchor,
    required this.endAnchor,
    required this.htmlNodeId,
    this.href,
    this.isParagraphBreak = false,
  });

  final String text;
  final TextStyle style;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;
  final String htmlNodeId;
  final String? href;
  final bool isParagraphBreak;
}
