import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Minimal, verified context for thread actions outside the detail page.
final class ThreadInteractionContext {
  const ThreadInteractionContext({
    required this.tid,
    required this.fid,
    required this.subject,
    required this.sourceUri,
    required this.firstPost,
    required this.canReply,
    required this.canRate,
    this.canComment = false,
  });

  final String tid;
  final String fid;
  final String subject;
  final Uri? sourceUri;
  final ThreadPost? firstPost;
  final bool canReply;
  final bool canRate;
  final bool canComment;
}

class ThreadInteractionContextLoader {
  const ThreadInteractionContextLoader(this._repository);

  final ThreadRepository _repository;

  Future<DataReadResult<ThreadInteractionContext, ThreadDetailReadCapabilities>>
  load(String sourceTid) async {
    final tid = sourceTid.trim();
    if (!RegExp(r'^\d+$').hasMatch(tid)) return _invalid();
    final result = await _repository.getThreadDetail(tid: tid, page: 1);
    return project(tid, result);
  }

  static DataReadResult<ThreadInteractionContext, ThreadDetailReadCapabilities>
  project(
    String tid,
    DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities> result,
  ) {
    if (result
        case DataReadFailure<
              ThreadDetailData,
              ThreadDetailReadCapabilities
            >()) {
      return result.failureOrNull!.retype();
    }
    final success =
        result
            as DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>;
    final data = success.data;
    if (data.tid.trim() != tid || data.currentPage != 1) return _invalid();
    final firstPosts = data.posts
        .where((post) => post.isFirst && post.pid.trim().isNotEmpty)
        .toList();
    // A missing or ambiguous first post must never select a reply as the
    // rating target. Thread replies can still work with a verified forum ID.
    final first = firstPosts.length == 1 ? firstPosts.single : null;
    final caps = success.capabilities;
    return DataReadSuccess(
      data: ThreadInteractionContext(
        tid: tid,
        fid: data.fid.trim(),
        subject: data.subject,
        sourceUri: data.desktopUrl?.trim().isNotEmpty == true
            ? Uri.tryParse(data.desktopUrl!.trim())
            : null,
        firstPost: first,
        canReply:
            data.fid.trim().isNotEmpty &&
            caps.supports(ThreadDetailCapability.replyAction),
        canComment:
            first != null &&
            caps.supports(ThreadDetailCapability.firstPostIdentity) &&
            caps.supports(ThreadDetailCapability.commentAction) &&
            first.commentUrl?.trim().isNotEmpty == true,
        canRate:
            first != null &&
            caps.supports(ThreadDetailCapability.firstPostIdentity) &&
            caps.supports(ThreadDetailCapability.ratingAction) &&
            first.rateUrl?.trim().isNotEmpty == true,
      ),
      capabilities: caps,
      metadata: success.metadata,
    );
  }

  static DataReadFailure<ThreadInteractionContext, ThreadDetailReadCapabilities>
  _invalid() => const DataReadFailure(
    kind: DataReadFailureKind.parse,
    code: 'thread_interaction_identity_invalid',
    diagnosticMessage: 'thread_interaction_identity_invalid',
  );
}
