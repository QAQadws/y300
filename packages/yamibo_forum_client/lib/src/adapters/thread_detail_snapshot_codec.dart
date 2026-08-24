import '../cache/forum_cache.dart';
import '../cache/forum_cache_key_canonicalizer.dart';
import '../contracts/thread_detail_models.dart';
import '../parsing/loose_json.dart';

class ThreadDetailSnapshotCodec
    implements ForumSnapshotCodec<ThreadDetailData> {
  const ThreadDetailSnapshotCodec();

  @override
  String get snapshotType =>
      ForumCacheKeyCanonicalizer.threadDetailSnapshotType;

  @override
  int get codecVersion => 1;

  @override
  int get parserVersion => 1;

  @override
  bool canDecodeVersion({
    required int codecVersion,
    required int parserVersion,
  }) =>
      codecVersion == this.codecVersion && parserVersion == this.parserVersion;

  @override
  Object? encode(ThreadDetailData value) {
    return <String, Object?>{
      'tid': value.tid,
      'fid': value.fid,
      'typeid': value.typeid,
      'typeName': value.typeName,
      'forumName': value.forumName,
      'forumUrl': value.forumUrl,
      'subject': value.subject,
      'author': value.author,
      'replies': value.replies,
      'views': value.views,
      'currentPage': value.currentPage,
      'perPage': value.perPage,
      'lastPage': value.lastPage,
      'previousPageUrl': value.previousPageUrl,
      'nextPageUrl': value.nextPageUrl,
      'reverseOrderUrl': value.reverseOrderUrl,
      'onlyAuthorUrl': value.onlyAuthorUrl,
      'favoriteUrl': value.favoriteUrl,
      'shareUrl': value.shareUrl,
      'homeUrl': value.homeUrl,
      'desktopUrl': value.desktopUrl,
      'posts': value.posts.map(_encodePost).toList(growable: false),
    };
  }

  @override
  ThreadDetailData decode(Object? json) {
    final map = LooseJson.map(json);
    return ThreadDetailData(
      tid: LooseJson.string(map['tid']),
      fid: LooseJson.string(map['fid']),
      typeid: LooseJson.string(map['typeid']),
      typeName: _nullableString(map['typeName']),
      forumName: _nullableString(map['forumName']),
      forumUrl: _nullableString(map['forumUrl']),
      subject: LooseJson.string(map['subject']),
      author: LooseJson.string(map['author']),
      replies: LooseJson.integer(map['replies']),
      views: LooseJson.integer(map['views']),
      currentPage: LooseJson.integer(map['currentPage'], fallback: 1),
      perPage: LooseJson.integer(map['perPage'], fallback: 20),
      lastPage: _nullableInt(map['lastPage']),
      previousPageUrl: _nullableString(map['previousPageUrl']),
      nextPageUrl: _nullableString(map['nextPageUrl']),
      reverseOrderUrl: _nullableString(map['reverseOrderUrl']),
      onlyAuthorUrl: _nullableString(map['onlyAuthorUrl']),
      favoriteUrl: _nullableString(map['favoriteUrl']),
      shareUrl: _nullableString(map['shareUrl']),
      homeUrl: _nullableString(map['homeUrl']),
      desktopUrl: _nullableString(map['desktopUrl']),
      posts: LooseJson.list(
        map['posts'],
      ).map((item) => _decodePost(LooseJson.map(item))).toList(growable: false),
    );
  }

  Map<String, Object?> _encodePost(ThreadPost value) {
    return <String, Object?>{
      'pid': value.pid,
      'author': value.author,
      'authorId': value.authorId,
      'message': value.message,
      'number': value.number,
      'isFirst': value.isFirst,
      'dateline': value.dateline,
      'avatarUrl': value.avatarUrl,
      'replyUrl': value.replyUrl,
      'editUrl': value.editUrl,
      'rateUrl': value.rateUrl,
      'commentUrl': value.commentUrl,
      'rateSummary': value.rateSummary,
      'ratingSummary': _encodeRatingSummary(value.ratingSummary),
      'poll': _encodePoll(value.poll),
      'tagLinks': value.tagLinks.map(_encodeTagLink).toList(growable: false),
      'comments': value.comments.map(_encodeComment).toList(growable: false),
      'attachmentImages': value.attachmentImages
          .map(_encodeAttachmentImage)
          .toList(growable: false),
    };
  }

  ThreadPost _decodePost(Map<String, dynamic> map) {
    return ThreadPost(
      pid: LooseJson.string(map['pid']),
      author: LooseJson.string(map['author']),
      authorId: LooseJson.string(map['authorId']),
      message: LooseJson.string(map['message']),
      number: LooseJson.integer(map['number']),
      isFirst: LooseJson.boolean(map['isFirst']),
      dateline: LooseJson.string(map['dateline']),
      avatarUrl: _nullableString(map['avatarUrl']),
      replyUrl: _nullableString(map['replyUrl']),
      editUrl: _nullableString(map['editUrl']),
      rateUrl: _nullableString(map['rateUrl']),
      commentUrl: _nullableString(map['commentUrl']),
      rateSummary: _nullableString(map['rateSummary']),
      ratingSummary: _decodeRatingSummary(map['ratingSummary']),
      poll: _decodePoll(map['poll']),
      tagLinks: LooseJson.list(map['tagLinks'])
          .map((item) => _decodeTagLink(LooseJson.map(item)))
          .toList(growable: false),
      comments: LooseJson.list(map['comments'])
          .map((item) => _decodeComment(LooseJson.map(item)))
          .toList(growable: false),
      attachmentImages: LooseJson.list(map['attachmentImages'])
          .map((item) => _decodeAttachmentImage(LooseJson.map(item)))
          .toList(growable: false),
    );
  }

  Map<String, Object?>? _encodePoll(ThreadPoll? value) {
    if (value == null) {
      return null;
    }
    return <String, Object?>{
      'isMultipleChoice': value.isMultipleChoice,
      'canVote': value.canVote,
      'maxChoices': value.maxChoices,
      'summary': value.summary,
      'deadlineText': value.deadlineText,
      'actionUrl': value.actionUrl,
      'formHash': value.formHash,
      'statusText': value.statusText,
      'options': value.options.map(_encodePollOption).toList(growable: false),
    };
  }

  ThreadPoll? _decodePoll(Object? value) {
    final map = LooseJson.map(value);
    if (map.isEmpty) {
      return null;
    }
    return ThreadPoll(
      isMultipleChoice: LooseJson.boolean(map['isMultipleChoice']),
      canVote: LooseJson.boolean(map['canVote'], fallback: true),
      maxChoices: _nullableInt(map['maxChoices']),
      summary: LooseJson.string(map['summary']),
      deadlineText: _nullableString(map['deadlineText']),
      actionUrl: _nullableString(map['actionUrl']),
      formHash: _nullableString(map['formHash']),
      statusText: _nullableString(map['statusText']),
      options: LooseJson.list(map['options'])
          .map((item) => _decodePollOption(LooseJson.map(item)))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _encodePollOption(ThreadPollOption value) {
    return <String, Object?>{
      'id': value.id,
      'label': value.label,
      'voteCount': value.voteCount,
      'percent': value.percent,
      'colorHex': value.colorHex,
    };
  }

  ThreadPollOption _decodePollOption(Map<String, dynamic> map) {
    return ThreadPollOption(
      id: LooseJson.string(map['id']),
      label: LooseJson.string(map['label']),
      voteCount: _nullableInt(map['voteCount']),
      percent: _nullableDouble(map['percent']),
      colorHex: _nullableString(map['colorHex']),
    );
  }

  Map<String, Object?>? _encodeRatingSummary(ThreadPostRatingSummary? value) {
    if (value == null) {
      return null;
    }
    return <String, Object?>{
      'participantText': value.participantText,
      'scoreText': value.scoreText,
      'viewAllUrl': value.viewAllUrl,
      'ratings': value.ratings.map(_encodeRating).toList(growable: false),
    };
  }

  ThreadPostRatingSummary? _decodeRatingSummary(Object? value) {
    final map = LooseJson.map(value);
    if (map.isEmpty) {
      return null;
    }
    return ThreadPostRatingSummary(
      participantText: LooseJson.string(map['participantText']),
      scoreText: LooseJson.string(map['scoreText']),
      viewAllUrl: _nullableString(map['viewAllUrl']),
      ratings: LooseJson.list(map['ratings'])
          .map((item) => _decodeRating(LooseJson.map(item)))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _encodeRating(ThreadPostRating value) {
    return <String, Object?>{
      'userName': value.userName,
      'score': value.score,
      'reason': value.reason,
      'userId': value.userId,
      'avatarUrl': value.avatarUrl,
      'dateline': value.dateline,
    };
  }

  ThreadPostRating _decodeRating(Map<String, dynamic> map) {
    return ThreadPostRating(
      userName: LooseJson.string(map['userName']),
      score: LooseJson.string(map['score']),
      reason: LooseJson.string(map['reason']),
      userId: _nullableString(map['userId']),
      avatarUrl: _nullableString(map['avatarUrl']),
      dateline: _nullableString(map['dateline']),
    );
  }

  Map<String, Object?> _encodeTagLink(ThreadPostTagLink value) {
    return <String, Object?>{
      'label': value.label,
      'url': value.url,
      'tagId': value.tagId,
    };
  }

  ThreadPostTagLink _decodeTagLink(Map<String, dynamic> map) {
    return ThreadPostTagLink(
      label: LooseJson.string(map['label']),
      url: LooseJson.string(map['url']),
      tagId: _nullableString(map['tagId']),
    );
  }

  Map<String, Object?> _encodeComment(ThreadPostCommentEntry value) {
    return <String, Object?>{
      'author': value.author,
      'message': value.message,
      'dateline': value.dateline,
      'authorId': value.authorId,
      'authorUrl': value.authorUrl,
      'avatarUrl': value.avatarUrl,
    };
  }

  ThreadPostCommentEntry _decodeComment(Map<String, dynamic> map) {
    return ThreadPostCommentEntry(
      author: LooseJson.string(map['author']),
      message: LooseJson.string(map['message']),
      dateline: LooseJson.string(map['dateline']),
      authorId: _nullableString(map['authorId']),
      authorUrl: _nullableString(map['authorUrl']),
      avatarUrl: _nullableString(map['avatarUrl']),
    );
  }

  Map<String, Object?> _encodeAttachmentImage(ForumPostAttachmentImage value) {
    return <String, Object?>{
      'aid': value.aid,
      'url': value.url,
      'attachment': value.attachment,
      'filename': value.filename,
      'attachimg': value.attachimg,
      'ext': value.ext,
    };
  }

  ForumPostAttachmentImage _decodeAttachmentImage(Map<String, dynamic> map) {
    return ForumPostAttachmentImage(
      aid: LooseJson.string(map['aid']),
      url: LooseJson.string(map['url']),
      attachment: LooseJson.string(map['attachment']),
      filename: LooseJson.string(map['filename']),
      attachimg: LooseJson.string(map['attachimg']),
      ext: LooseJson.string(map['ext']),
    );
  }

  String? _nullableString(Object? value) {
    final text = LooseJson.string(value).trim();
    return text.isEmpty ? null : text;
  }

  int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString());
  }

  double? _nullableDouble(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
