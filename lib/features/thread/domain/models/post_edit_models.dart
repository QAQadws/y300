import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/post_edit_failure_models.dart';

export 'post_edit_failure_models.dart';

/// App-owned route identity discovered from one rendered thread post.
final class PostEditTarget {
  const PostEditTarget({
    required this.editUri,
    required this.fid,
    required this.tid,
    required this.pid,
    required this.page,
    required this.isFirstPost,
  });

  final Uri editUri;
  final String fid;
  final String tid;
  final String pid;
  final int page;
  final bool isFirstPost;

  ThreadPostEditTarget toClientTarget() => ThreadPostEditTarget(
    formUri: editUri,
    fid: fid,
    tid: tid,
    pid: pid,
    page: page,
    kind: isFirstPost
        ? ThreadPostEditTargetKind.firstPost
        : ThreadPostEditTargetKind.reply,
  );

  @override
  bool operator ==(Object other) =>
      other is PostEditTarget &&
      other.editUri == editUri &&
      other.fid == fid &&
      other.tid == tid &&
      other.pid == pid &&
      other.page == page &&
      other.isFirstPost == isFirstPost;

  @override
  int get hashCode => Object.hash(editUri, fid, tid, pid, page, isFirstPost);
}

final class PostEditTargetParseResult {
  const PostEditTargetParseResult.success(PostEditTarget target)
    : target = target,
      failure = null;

  const PostEditTargetParseResult.failure(PostEditTargetParseFailure failure)
    : target = null,
      failure = failure;

  final PostEditTarget? target;
  final PostEditTargetParseFailure? failure;

  bool get isSuccess => target != null;
}

/// App-owned attachment registry for one native edit page generation.
final class PostEditAttachmentSession {
  PostEditAttachmentSession({
    required Map<String, ThreadPostEditImageAttachment> existingImagesByAid,
    Set<String> deletingAids = const <String>{},
    Set<String> deletedAidTombstones = const <String>{},
  }) : existingImagesByAid = Map.unmodifiable(existingImagesByAid),
       deletingAids = Set.unmodifiable(deletingAids),
       deletedAidTombstones = Set.unmodifiable(deletedAidTombstones);

  factory PostEditAttachmentSession.fromImages(
    Iterable<ThreadPostEditImageAttachment> images, {
    Set<String> deletingAids = const <String>{},
    Set<String> deletedAidTombstones = const <String>{},
  }) => PostEditAttachmentSession(
    existingImagesByAid: {for (final image in images) image.aid: image},
    deletingAids: deletingAids,
    deletedAidTombstones: deletedAidTombstones,
  );

  final Map<String, ThreadPostEditImageAttachment> existingImagesByAid;
  final Set<String> deletingAids;
  final Set<String> deletedAidTombstones;

  PostEditAttachmentSession copyWith({
    Map<String, ThreadPostEditImageAttachment>? existingImagesByAid,
    Set<String>? deletingAids,
    Set<String>? deletedAidTombstones,
  }) => PostEditAttachmentSession(
    existingImagesByAid: existingImagesByAid ?? this.existingImagesByAid,
    deletingAids: deletingAids ?? this.deletingAids,
    deletedAidTombstones: deletedAidTombstones ?? this.deletedAidTombstones,
  );
}

enum PostEditAttachmentDeleteOutcome { deleted, notDeleted, unconfirmed }
