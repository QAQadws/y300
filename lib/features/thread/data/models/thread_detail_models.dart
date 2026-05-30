import 'package:y300/core/utils/parse_utils.dart';

class ForumPostAttachmentImage {
  const ForumPostAttachmentImage({
    required this.aid,
    required this.url,
    required this.attachment,
    required this.filename,
    required this.attachimg,
    required this.ext,
  });

  final String aid;
  final String url;
  final String attachment;
  final String filename;
  final String attachimg;
  final String ext;

  factory ForumPostAttachmentImage.fromJson(JsonMap json) {
    return ForumPostAttachmentImage(
      aid: ParseUtils.asString(json['aid']),
      url: ParseUtils.asString(json['url']),
      attachment: ParseUtils.asString(json['attachment']),
      filename: ParseUtils.asString(json['filename']),
      attachimg: ParseUtils.asString(json['attachimg']),
      ext: ParseUtils.asString(json['ext']),
    );
  }
}

class ThreadPost {
  ThreadPost({
    required this.pid,
    required this.author,
    required this.authorId,
    required this.message,
    required this.number,
    required this.isFirst,
    required this.dateline,
    this.attachmentImages = const <ForumPostAttachmentImage>[],
  });

  final String pid;
  final String author;
  final String authorId;
  final String message;
  final int number;
  final bool isFirst;
  final String dateline;
  /// Raw Discuz attachment metadata. Entries may be images or non-image files.
  final List<ForumPostAttachmentImage> attachmentImages;

  factory ThreadPost.fromJson(JsonMap json) {
    return ThreadPost(
      pid: ParseUtils.asString(json['pid']),
      author: ParseUtils.asString(json['author']),
      authorId: ParseUtils.asString(json['authorid']),
      message: ParseUtils.asString(json['message']),
      number: ParseUtils.asInt(json['number']),
      isFirst: ParseUtils.asString(json['first']) == '1',
      dateline: ParseUtils.asString(json['dateline']),
      attachmentImages: _parseAttachmentImages(json['attachments']),
    );
  }

  static List<ForumPostAttachmentImage> _parseAttachmentImages(dynamic value) {
    final attachments = ParseUtils.asMap(value);
    if (attachments.isEmpty) {
      return const <ForumPostAttachmentImage>[];
    }
    return attachments.values
        .map(ParseUtils.asMap)
        .where((item) => item.isNotEmpty)
        .map(ForumPostAttachmentImage.fromJson)
        .where((item) => item.attachment.trim().isNotEmpty)
        .toList(growable: false);
  }
}

class ThreadDetailData {
  ThreadDetailData({
    required this.tid,
    required this.fid,
    this.typeid = '',
    required this.subject,
    required this.author,
    required this.replies,
    required this.views,
    required this.currentPage,
    required this.perPage,
    required this.posts,
  });

  final String tid;
  final String fid;
  final String typeid;
  final String subject;
  final String author;
  final int replies;
  final int views;
  final int currentPage;
  final int perPage;
  final List<ThreadPost> posts;

  /// Discuz 返回 replies 为回帖数，不含主楼，故这里使用 <= 保守判断。
  bool get hasMore {
    final loaded = currentPage * perPage;
    return loaded <= replies;
  }

  factory ThreadDetailData.fromVariables(
    JsonMap variables, {
    required int page,
  }) {
    final thread = ParseUtils.asMap(variables['thread']);
    final perPage = ParseUtils.asInt(variables['ppp'], fallback: 20);

    return ThreadDetailData(
      tid: ParseUtils.asString(thread['tid']),
      fid: ParseUtils.asString(
        variables['fid'],
        fallback: ParseUtils.asString(thread['fid']),
      ),
      typeid: ParseUtils.asString(
        thread['typeid'],
        fallback: ParseUtils.asString(variables['typeid']),
      ),
      subject: ParseUtils.asString(thread['subject']),
      author: ParseUtils.asString(thread['author']),
      replies: ParseUtils.asInt(thread['replies']),
      views: ParseUtils.asInt(thread['views']),
      currentPage: page,
      perPage: perPage,
      posts: ParseUtils.asList(
        variables['postlist'],
      ).map((item) => ThreadPost.fromJson(ParseUtils.asMap(item))).toList(),
    );
  }
}
