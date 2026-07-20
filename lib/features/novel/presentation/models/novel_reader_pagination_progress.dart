import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';

/// An immutable snapshot containing only page boundaries that are final.
///
/// A partial snapshot never exposes the composer's open page. This guarantees
/// that a page already displayed by the reader cannot gain content later.
@immutable
final class NovelReaderPaginationProgress {
  const NovelReaderPaginationProgress({
    required this.plan,
    required this.isComplete,
    required this.processedAtomCount,
    required this.totalAtomCount,
  });

  final NovelReaderPaginationPlan plan;
  final bool isComplete;
  final int processedAtomCount;
  final int totalAtomCount;

  bool get isTotalPageCountKnown => isComplete;
}
