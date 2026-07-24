import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/cache/domain/services/cache_key_canonicalizer.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

class ThreadDetailSnapshotCodec implements SnapshotCodec<ThreadDetailData> {
  const ThreadDetailSnapshotCodec();

  @override
  String get snapshotType => CacheKeyCanonicalizer.threadDetailSnapshotType;

  @override
  int get codecVersion => 1;

  @override
  int get parserVersion => 1;

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
    final map = ParseUtils.asMap(json);
    return ThreadDetailData(
      tid: ParseUtils.asString(map['tid']),
      fid: ParseUtils.asString(map['fid']),
      typeid: ParseUtils.asString(map['typeid']),
      typeName: _nullableString(map['typeName']),
      forumName: _nullableString(map['forumName']),
      forumUrl: _nullableString(map['forumUrl']),
      subject: ParseUtils.asString(map['subject']),
      author: ParseUtils.asString(map['author']),
      replies: ParseUtils.asInt(map['replies']),
      views: ParseUtils.asInt(map['views']),
      currentPage: ParseUtils.asInt(map['currentPage'], fallback: 1),
      perPage: ParseUtils.asInt(map['perPage'], fallback: 20),
      lastPage: _nullableInt(map['lastPage']),
      previousPageUrl: _nullableString(map['previousPageUrl']),
      nextPageUrl: _nullableString(map['nextPageUrl']),
      reverseOrderUrl: _nullableString(map['reverseOrderUrl']),
      onlyAuthorUrl: _nullableString(map['onlyAuthorUrl']),
      favoriteUrl: _nullableString(map['favoriteUrl']),
      shareUrl: _nullableString(map['shareUrl']),
      homeUrl: _nullableString(map['homeUrl']),
      desktopUrl: _nullableString(map['desktopUrl']),
      posts: ParseUtils.asList(map['posts'])
          .map((item) => _decodePost(ParseUtils.asMap(item)))
          .toList(growable: false),
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
      pid: ParseUtils.asString(map['pid']),
      author: ParseUtils.asString(map['author']),
      authorId: ParseUtils.asString(map['authorId']),
      message: ParseUtils.asString(map['message']),
      number: ParseUtils.asInt(map['number']),
      isFirst: ParseUtils.asBool(map['isFirst']),
      dateline: ParseUtils.asString(map['dateline']),
      avatarUrl: _nullableString(map['avatarUrl']),
      replyUrl: _nullableString(map['replyUrl']),
      rateUrl: _nullableString(map['rateUrl']),
      commentUrl: _nullableString(map['commentUrl']),
      rateSummary: _nullableString(map['rateSummary']),
      ratingSummary: _decodeRatingSummary(map['ratingSummary']),
      poll: _decodePoll(map['poll']),
      tagLinks: ParseUtils.asList(map['tagLinks'])
          .map((item) => _decodeTagLink(ParseUtils.asMap(item)))
          .toList(growable: false),
      comments: ParseUtils.asList(map['comments'])
          .map((item) => _decodeComment(ParseUtils.asMap(item)))
          .toList(growable: false),
      attachmentImages: ParseUtils.asList(map['attachmentImages'])
          .map((item) => _decodeAttachmentImage(ParseUtils.asMap(item)))
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
    final map = ParseUtils.asMap(value);
    if (map.isEmpty) {
      return null;
    }
    return ThreadPoll(
      isMultipleChoice: ParseUtils.asBool(map['isMultipleChoice']),
      canVote: ParseUtils.asBool(map['canVote'], fallback: true),
      maxChoices: _nullableInt(map['maxChoices']),
      summary: ParseUtils.asString(map['summary']),
      deadlineText: _nullableString(map['deadlineText']),
      actionUrl: _nullableString(map['actionUrl']),
      formHash: _nullableString(map['formHash']),
      statusText: _nullableString(map['statusText']),
      options: ParseUtils.asList(map['options'])
          .map((item) => _decodePollOption(ParseUtils.asMap(item)))
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
      id: ParseUtils.asString(map['id']),
      label: ParseUtils.asString(map['label']),
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
    final map = ParseUtils.asMap(value);
    if (map.isEmpty) {
      return null;
    }
    return ThreadPostRatingSummary(
      participantText: ParseUtils.asString(map['participantText']),
      scoreText: ParseUtils.asString(map['scoreText']),
      viewAllUrl: _nullableString(map['viewAllUrl']),
      ratings: ParseUtils.asList(map['ratings'])
          .map((item) => _decodeRating(ParseUtils.asMap(item)))
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
      userName: ParseUtils.asString(map['userName']),
      score: ParseUtils.asString(map['score']),
      reason: ParseUtils.asString(map['reason']),
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
      label: ParseUtils.asString(map['label']),
      url: ParseUtils.asString(map['url']),
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
      author: ParseUtils.asString(map['author']),
      message: ParseUtils.asString(map['message']),
      dateline: ParseUtils.asString(map['dateline']),
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
      aid: ParseUtils.asString(map['aid']),
      url: ParseUtils.asString(map['url']),
      attachment: ParseUtils.asString(map['attachment']),
      filename: ParseUtils.asString(map['filename']),
      attachimg: ParseUtils.asString(map['attachimg']),
      ext: ParseUtils.asString(map['ext']),
    );
  }

  String? _nullableString(Object? value) {
    final text = ParseUtils.asString(value).trim();
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
