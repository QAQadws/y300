import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_card.dart';

/// A standalone, lazy comment list.
///
/// The reader-tail integration is deliberately outside this widget. Keeping
/// this surface scrollable on its own makes the Phase 2 component testable and
/// prevents a second reader-specific pagination or lifecycle state machine.
class ComicCommentListSurface extends StatelessWidget {
  const ComicCommentListSurface({
    super.key,
    required this.sourceTid,
    this.result,
    this.isLoading = false,
    this.imageHeaderBuilder,
    this.onRetry,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 24),
  });

  final String sourceTid;
  final ComicCommentLoadResult? result;
  final bool isLoading;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final VoidCallback? onRetry;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const _CommentLoadingState();
    }

    final loadResult = result;
    if (loadResult == null ||
        loadResult.status == ComicCommentLoadStatus.empty) {
      return const _CommentEmptyState();
    }
    if (loadResult.status == ComicCommentLoadStatus.failure ||
        loadResult.status == ComicCommentLoadStatus.cancelled) {
      return _CommentFailureState(onRetry: onRetry);
    }
    if (loadResult.items.isEmpty) {
      return const _CommentEmptyState();
    }

    final hasPartialFailure =
        loadResult.status == ComicCommentLoadStatus.partialFailure;
    final itemCount = loadResult.items.length + (hasPartialFailure ? 1 : 0);
    return ListView.builder(
      key: const Key('comic-comment-list'),
      padding: padding,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= loadResult.items.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _CommentFailureState(onRetry: onRetry, compact: true),
          );
        }
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == loadResult.items.length - 1 ? 0 : 10,
          ),
          child: ComicCommentCard(
            comment: loadResult.items[index],
            sourceTid: sourceTid,
            imageHeaderBuilder: imageHeaderBuilder,
          ),
        );
      },
    );
  }
}

class _CommentLoadingState extends StatelessWidget {
  const _CommentLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('comic-comment-loading'),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _CommentEmptyState extends StatelessWidget {
  const _CommentEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('comic-comment-empty'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('暂无评论', style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

class _CommentFailureState extends StatelessWidget {
  const _CommentFailureState({this.onRetry, this.compact = false});

  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '评论暂不可用',
            key: const Key('comic-comment-failure'),
            textAlign: TextAlign.center,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ],
    );
    return Center(
      key: const Key('comic-comment-failure-state'),
      child: Padding(padding: EdgeInsets.all(compact ? 4 : 24), child: content),
    );
  }
}
