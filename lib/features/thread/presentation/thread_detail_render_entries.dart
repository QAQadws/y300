import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projection.dart';

/// Builds stable visual entries without parsing or caching post bodies.
@immutable
class ThreadDetailRenderEntryPlanner {
  const ThreadDetailRenderEntryPlanner();

  List<ThreadDetailRenderEntry> buildEntries({
    required List<ThreadPost> posts,
    String? targetPid,
    ThreadPostLanding landing = ThreadPostLanding.top,
  }) {
    return buildProjectionEntries(
      posts: [
        for (final post in posts)
          ThreadDetailPostProjection(sourcePost: post, displayPost: post),
      ],
      targetPid: targetPid,
      landing: landing,
    );
  }

  List<ThreadDetailRenderEntry> buildProjectionEntries({
    required List<ThreadDetailPostProjection> posts,
    String? targetPid,
    ThreadPostLanding landing = ThreadPostLanding.top,
  }) {
    final entries = <ThreadDetailRenderEntry>[];
    final normalizedTargetPid = targetPid?.trim();
    for (var index = 0; index < posts.length; index++) {
      final post = posts[index];
      if (landing == ThreadPostLanding.bodyEnd &&
          post.sourcePost.pid == normalizedTargetPid) {
        final pid = post.sourcePost.pid;
        entries.addAll([
          ThreadDetailRenderEntry.postHeader(
            key: 'thread-post-header-entry-$pid',
            sourcePost: post.sourcePost,
            displayPost: post.displayPost,
            postIndex: index,
          ),
          ThreadDetailRenderEntry.postBody(
            key: 'thread-post-body-entry-$pid',
            sourcePost: post.sourcePost,
            displayPost: post.displayPost,
            postIndex: index,
          ),
          ThreadDetailRenderEntry.postFooter(
            key: 'thread-post-footer-entry-$pid',
            sourcePost: post.sourcePost,
            displayPost: post.displayPost,
            postIndex: index,
          ),
        ]);
        continue;
      }
      entries.add(
        ThreadDetailRenderEntry.postCard(
          key: 'thread-post-card-entry-${post.sourcePost.pid}',
          sourcePost: post.sourcePost,
          displayPost: post.displayPost,
          postIndex: index,
        ),
      );
    }
    entries.add(const ThreadDetailRenderEntry.pagination());
    if (normalizedTargetPid?.isNotEmpty == true) {
      entries.add(const ThreadDetailRenderEntry.targetSpacer());
    }
    return List<ThreadDetailRenderEntry>.unmodifiable(entries);
  }
}

enum ThreadDetailRenderEntryKind {
  postCard,
  postHeader,
  postBody,
  postFooter,
  pagination,
  targetSpacer,
}

@immutable
class ThreadDetailRenderEntry {
  const ThreadDetailRenderEntry._({
    required this.kind,
    required this.key,
    this.sourcePost,
    this.displayPost,
    required this.postIndex,
  });

  const ThreadDetailRenderEntry.postCard({
    required String key,
    required ThreadPost sourcePost,
    required ThreadPost displayPost,
    required int postIndex,
  }) : this._(
         kind: ThreadDetailRenderEntryKind.postCard,
         key: key,
         sourcePost: sourcePost,
         displayPost: displayPost,
         postIndex: postIndex,
       );

  const ThreadDetailRenderEntry.postHeader({
    required String key,
    required ThreadPost sourcePost,
    required ThreadPost displayPost,
    required int postIndex,
  }) : this._(
         kind: ThreadDetailRenderEntryKind.postHeader,
         key: key,
         sourcePost: sourcePost,
         displayPost: displayPost,
         postIndex: postIndex,
       );

  const ThreadDetailRenderEntry.postBody({
    required String key,
    required ThreadPost sourcePost,
    required ThreadPost displayPost,
    required int postIndex,
  }) : this._(
         kind: ThreadDetailRenderEntryKind.postBody,
         key: key,
         sourcePost: sourcePost,
         displayPost: displayPost,
         postIndex: postIndex,
       );

  const ThreadDetailRenderEntry.postFooter({
    required String key,
    required ThreadPost sourcePost,
    required ThreadPost displayPost,
    required int postIndex,
  }) : this._(
         kind: ThreadDetailRenderEntryKind.postFooter,
         key: key,
         sourcePost: sourcePost,
         displayPost: displayPost,
         postIndex: postIndex,
       );

  const ThreadDetailRenderEntry.pagination()
    : this._(
        kind: ThreadDetailRenderEntryKind.pagination,
        key: 'thread-detail-pagination',
        postIndex: -1,
      );

  const ThreadDetailRenderEntry.targetSpacer()
    : this._(
        kind: ThreadDetailRenderEntryKind.targetSpacer,
        key: 'thread-detail-target-scroll-spacer',
        postIndex: -1,
      );

  final ThreadDetailRenderEntryKind kind;
  final String key;
  final ThreadPost? sourcePost;
  final ThreadPost? displayPost;
  final int postIndex;
}
