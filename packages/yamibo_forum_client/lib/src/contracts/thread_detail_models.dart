/// Source-neutral thread, post, attachment, poll, and navigation models.
library;

/// Source-neutral forum post attachment image.
class ForumPostAttachmentImage {
  /// Creates a [ForumPostAttachmentImage].
  const ForumPostAttachmentImage({
    required this.aid,
    required this.url,
    required this.attachment,
    required this.filename,
    required this.attachimg,
    required this.ext,
  });

  /// Stable attachment identifier.
  final String aid;

  /// Source-provided URL after validation.
  final String url;

  /// Relative or absolute attachment path supplied by Discuz.
  final String attachment;

  /// Source-provided display filename.
  final String filename;

  /// Raw Discuz flag indicating whether this attachment is an image.
  final String attachimg;

  /// Source-provided lower-case file extension when available.
  final String ext;
}

/// Source-neutral thread poll option.
class ThreadPollOption {
  /// Creates a [ThreadPollOption].
  const ThreadPollOption({
    required this.id,
    required this.label,
    this.voteCount,
    this.percent,
    this.colorHex,
  });

  /// Stable option identifier submitted by the poll command.
  final String id;

  /// Human-readable option label.
  final String label;

  /// Current vote count when exposed by the source.
  final int? voteCount;

  /// Current vote percentage when exposed by the source.
  final double? percent;

  /// Optional source-provided chart color.
  final String? colorHex;
}

/// Source-neutral thread poll.
class ThreadPoll {
  /// Creates a [ThreadPoll].
  const ThreadPoll({
    required this.isMultipleChoice,
    required this.summary,
    required this.options,
    this.canVote = true,
    this.maxChoices,
    this.deadlineText,
    this.statusText,
  });

  /// Whether voters may select more than one option.
  final bool isMultipleChoice;

  /// Whether the current source proves that voting is available.
  final bool canVote;

  /// Maximum selectable options for a multiple-choice poll.
  final int? maxChoices;

  /// Source-provided poll prompt or summary.
  final String summary;

  /// Source-provided deadline text, when available.
  final String? deadlineText;

  /// Source-provided closed or participation status text.
  final String? statusText;

  /// Poll options in server display order.
  final List<ThreadPollOption> options;
}

/// Source-neutral thread post rating.
class ThreadPostRating {
  /// Creates a [ThreadPostRating].
  const ThreadPostRating({
    required this.userName,
    required this.score,
    required this.reason,
    this.userId,
    this.avatarUrl,
    this.dateline,
  });

  /// Source-provided rater display name.
  final String userName;

  /// Source-provided signed score text.
  final String score;

  /// Rating reason, which may be empty.
  final String reason;

  /// Stable user identifier.
  final String? userId;

  /// Validated rater avatar URL, when available.
  final String? avatarUrl;

  /// Source-provided rating time text.
  final String? dateline;
}

/// Source-neutral thread post rating summary.
class ThreadPostRatingSummary {
  /// Creates a [ThreadPostRatingSummary].
  const ThreadPostRatingSummary({
    required this.participantText,
    required this.scoreText,
    required this.ratings,
    this.viewAllUrl,
  });

  /// Source-provided participant summary text.
  final String participantText;

  /// Source-provided aggregate score text.
  final String scoreText;

  /// Preview ratings in server display order.
  final List<ThreadPostRating> ratings;

  /// Validated action URL proving that full ratings are available.
  final String? viewAllUrl;
}

/// Source-neutral thread post tag link.
class ThreadPostTagLink {
  /// Creates a [ThreadPostTagLink].
  const ThreadPostTagLink({required this.label, required this.url, this.tagId});

  /// Human-readable tag label.
  final String label;

  /// Source-provided URL after validation.
  final String url;

  /// Stable tag identifier parsed from [url], when available.
  final String? tagId;
}

/// Source-neutral thread post comment entry.
class ThreadPostCommentEntry {
  /// Creates a [ThreadPostCommentEntry].
  const ThreadPostCommentEntry({
    required this.author,
    required this.message,
    required this.dateline,
    this.authorId,
    this.authorUrl,
    this.avatarUrl,
  });

  /// Source-provided comment author display name.
  final String author;

  /// Renderable comment body markup.
  final String message;

  /// Source-provided comment time text.
  final String dateline;

  /// Stable author identifier.
  final String? authorId;

  /// Validated author profile URL, when available.
  final String? authorUrl;

  /// Validated author avatar URL, when available.
  final String? avatarUrl;
}

/// Source-neutral thread post.
class ThreadPost {
  /// Creates a [ThreadPost].
  ThreadPost({
    required this.pid,
    required this.author,
    required this.authorId,
    required this.message,
    required this.number,
    required this.isFirst,
    required this.dateline,
    this.avatarUrl,
    this.replyUrl,
    this.editUrl,
    this.rateUrl,
    this.commentUrl,
    this.rateSummary,
    this.ratingSummary,
    this.poll,
    this.tagLinks = const <ThreadPostTagLink>[],
    this.comments = const <ThreadPostCommentEntry>[],
    this.attachmentImages = const <ForumPostAttachmentImage>[],
  });

  /// Stable post identifier.
  final String pid;

  /// Source-provided post author display name.
  final String author;

  /// Stable author identifier.
  final String authorId;

  /// Renderable post body markup.
  final String message;

  /// One-based floor number when proved by the source.
  final int number;

  /// Whether this is the thread's first post.
  final bool isFirst;

  /// Source-provided post time text.
  final String dateline;

  /// Validated author avatar URL, when available.
  final String? avatarUrl;

  /// Validated reply action URL, when available.
  final String? replyUrl;

  /// Validated edit action URL, when available.
  final String? editUrl;

  /// Validated rating action URL, when available.
  final String? rateUrl;

  /// Validated comment action URL, when available.
  final String? commentUrl;

  /// Compact source-provided rating summary.
  final String? rateSummary;

  /// Structured rating summary, when supported by the source.
  final ThreadPostRatingSummary? ratingSummary;

  /// Structured poll content for the first post, when present.
  final ThreadPoll? poll;

  /// Thread tag links in source order.
  final List<ThreadPostTagLink> tagLinks;

  /// Post comments in source order.
  final List<ThreadPostCommentEntry> comments;

  /// Raw Discuz attachment metadata. Entries may be images or non-image files.
  final List<ForumPostAttachmentImage> attachmentImages;
}

/// Source-neutral thread detail data.
class ThreadDetailData {
  /// Creates a [ThreadDetailData].
  ThreadDetailData({
    required this.tid,
    required this.fid,
    this.typeid = '',
    this.typeName,
    this.forumName,
    this.forumUrl,
    required this.subject,
    required this.author,
    required this.replies,
    required this.views,
    required this.currentPage,
    required this.perPage,
    required this.posts,
    this.lastPage,
    this.previousPageUrl,
    this.nextPageUrl,
    this.reverseOrderUrl,
    this.onlyAuthorUrl,
    this.favoriteUrl,
    this.shareUrl,
    this.homeUrl,
    this.desktopUrl,
  });

  /// Stable thread identifier.
  final String tid;

  /// Stable forum identifier.
  final String fid;

  /// Stable Discuz thread-type identifier, or an empty string when absent.
  final String typeid;

  /// Human-readable thread-type name, when available.
  final String? typeName;

  /// Human-readable forum name, when available.
  final String? forumName;

  /// Validated forum URL, when available.
  final String? forumUrl;

  /// Source-provided thread subject.
  final String subject;

  /// Source-provided thread author display name.
  final String author;

  /// Server-declared reply count, excluding the first post.
  final int replies;

  /// Server-declared view count.
  final int views;

  /// Current one-based server page.
  final int currentPage;

  /// Server-declared or conservatively inferred page size.
  final int perPage;

  /// Posts in stable server order.
  final List<ThreadPost> posts;

  /// Exact or inferred last page when the source exposes it.
  final int? lastPage;

  /// Validated previous-page URL, when available.
  final String? previousPageUrl;

  /// Validated next-page URL, when available.
  final String? nextPageUrl;

  /// Validated reverse-order view URL, when available.
  final String? reverseOrderUrl;

  /// Validated author-only view URL, when available.
  final String? onlyAuthorUrl;

  /// Validated favorite action entry URL, when available.
  final String? favoriteUrl;

  /// Validated share URL, when available.
  final String? shareUrl;

  /// Validated forum-home URL, when available.
  final String? homeUrl;

  /// Validated desktop thread URL, when available.
  final String? desktopUrl;

  /// Discuz 返回 replies 为回帖数，不含主楼，故这里使用 <= 保守判断。
  bool get hasMore {
    if (nextPageUrl != null) {
      return true;
    }
    final knownLastPage = lastPage;
    if (knownLastPage != null) {
      return currentPage < knownLastPage;
    }
    final loaded = currentPage * perPage;
    return loaded <= replies;
  }
}
