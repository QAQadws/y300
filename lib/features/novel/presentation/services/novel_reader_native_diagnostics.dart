import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../models/novel_reader_pagination_exception.dart';
import 'novel_reader_native_anchor_binder.dart';
import 'novel_reader_native_layout_scope.dart';

enum NovelReaderNativeDiagnosticMode { paged, scrolling }

/// Local counters at source and layout boundaries. Values come from bounded
/// counts and fixed categories. The sink never receives content or identity.
final class NovelReaderNativeDiagnostics {
  const NovelReaderNativeDiagnostics();

  void prepared(ForumBodyDocument document) {
    final issues = <ForumBodyIssueCode, int>{};
    for (final issue in document.issues) {
      issues[issue.code] = (issues[issue.code] ?? 0) + 1;
    }
    _emit('prepared', {
      'parsedNodes': document.parsedNodeCount,
      'styles': document.uniqueStyleCount,
      'formats': {
        for (final entry in document.elementCounts.entries)
          entry.key.name: entry.value,
      },
      'issues': {
        for (final entry in issues.entries) entry.key.name: entry.value,
      },
    });
  }

  void completed(
    NovelReaderNativeDiagnosticMode mode,
    ForumBodyTextPageSession session,
  ) {
    _emit('completed', {
      'mode': mode.name,
      'slices': session.snapshot.length,
      'styleIssues': session.pendingStyleIssueCount,
      'droppedStyleIssues': session.droppedStyleIssueCount,
    });
  }

  void failed(NovelReaderNativeDiagnosticMode mode, Object error) {
    final category = switch (error) {
      NovelReaderPaginationException(code: 'paginationCancelled') ||
      ForumBodyTextPageSessionException(
        failure: ForumBodyTextPageSessionFailure.ownerRetired,
      ) => null,
      NovelReaderPaginationException(
        code: 'backgroundPaginationIdle' || 'targetPageWaitExceeded',
      ) =>
        'timeout',
      NovelReaderPaginationException(code: 'paginationPrefixMismatch') =>
        'prefixMismatch',
      NovelReaderPaginationException() => 'navigation',
      ForumBodyParseException(:final failure) => 'parse.${failure.name}',
      NovelReaderNativeAnchorBindingException(:final failure) =>
        'source.${failure.name}',
      NovelReaderNativeLayoutInputException(:final failure) =>
        'input.${failure.name}',
      ForumBodyBlockFlowException(:final failure) => 'flow.${failure.name}',
      ForumBodyTableException(:final failure) => 'table.${failure.name}',
      ForumBodyTextPageException(:final failure) => 'compose.${failure.name}',
      ForumBodyTextPageSessionException(:final failure) =>
        'session.${failure.name}',
      ForumBodyParagraphBudgetException(:final failure) =>
        'resources.${failure.name}',
      _ => 'unexpected',
    };
    if (category == null) return;
    _emit('failed', {'mode': mode.name, 'category': category, 'count': 1});
  }

  void _emit(String event, Map<String, Object?> fields) {
    debugPrint(
      '[NovelReaderNative] ${jsonEncode({'event': event, ...fields})}',
    );
  }
}
