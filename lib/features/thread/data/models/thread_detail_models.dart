import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/utils/parse_utils.dart';

class ThreadAttachment {
  ThreadAttachment({
    required this.aid,
    required this.url,
    required this.attachment,
    required this.isImage,
  });

  final String aid;
  final String url;
  final String attachment;
  final bool isImage;

  factory ThreadAttachment.fromJson(JsonMap json, {String fallbackAid = ''}) {
    final aid = ParseUtils.asString(json['aid']);
    final resolvedAid = aid.isNotEmpty ? aid : fallbackAid;
    final attachImg = ParseUtils.asString(json['attachimg']);
    final isImageFlag = ParseUtils.asString(json['isimage']);

    return ThreadAttachment(
      aid: resolvedAid,
      url: ParseUtils.asString(json['url']),
      attachment: ParseUtils.asString(json['attachment']),
      isImage: attachImg == '1' || isImageFlag == '1',
    );
  }

  String resolveUrl({String siteBaseUrl = AppConfig.siteBaseUrl}) {
    if (url.isEmpty || attachment.isEmpty) {
      return '';
    }
    final base = siteBaseUrl.endsWith('/')
        ? siteBaseUrl.substring(0, siteBaseUrl.length - 1)
        : siteBaseUrl;
    final normalizedUrl = url.startsWith('/') ? url.substring(1) : url;
    final normalizedAttachment = attachment.startsWith('/')
        ? attachment.substring(1)
        : attachment;
    final separator = normalizedUrl.endsWith('/') ? '' : '/';
    return '$base/$normalizedUrl$separator$normalizedAttachment';
  }
}

class ThreadPostContent {
  const ThreadPostContent({required this.html, required this.trailingImageUrls});

  final String html;
  final List<String> trailingImageUrls;
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
    Map<String, ThreadAttachment>? attachments,
  }) : attachments = attachments ?? const <String, ThreadAttachment>{};

  final String pid;
  final String author;
  final String authorId;
  final String message;
  final int number;
  final bool isFirst;
  final String dateline;
  final Map<String, ThreadAttachment> attachments;

  factory ThreadPost.fromJson(JsonMap json) {
    final attachmentsMap = ParseUtils.asMap(json['attachments']);
    final attachments = <String, ThreadAttachment>{};
    attachmentsMap.forEach((key, value) {
      final attachmentJson = ParseUtils.asMap(value);
      final attachment =
          ThreadAttachment.fromJson(attachmentJson, fallbackAid: key);
      if (attachment.aid.isNotEmpty) {
        attachments[attachment.aid] = attachment;
      }
    });

    return ThreadPost(
      pid: ParseUtils.asString(json['pid']),
      author: ParseUtils.asString(json['author']),
      authorId: ParseUtils.asString(json['authorid']),
      message: ParseUtils.asString(json['message']),
      number: ParseUtils.asInt(json['number']),
      isFirst: ParseUtils.asString(json['first']) == '1',
      dateline: ParseUtils.asString(json['dateline']),
      attachments: attachments,
    );
  }

  ThreadPostContent buildContent({String siteBaseUrl = AppConfig.siteBaseUrl}) {
    // Replace [attach] placeholders with image tags; append unreferenced images.
    final usedAttachmentIds = <String>{};
    final html = message.replaceAllMapped(_attachmentPattern, (match) {
      final aid = match.group(1) ?? '';
      final attachment = attachments[aid];
      if (attachment == null || !attachment.isImage) {
        return '';
      }
      final url = attachment.resolveUrl(siteBaseUrl: siteBaseUrl);
      if (url.isEmpty) {
        return '';
      }
      usedAttachmentIds.add(aid);
      return '<img src="$url" />';
    });

    final trailingImages = attachments.values
        .where((attachment) =>
            attachment.isImage && !usedAttachmentIds.contains(attachment.aid))
        .map((attachment) =>
            attachment.resolveUrl(siteBaseUrl: siteBaseUrl))
        .where((url) => url.isNotEmpty)
        .toList(growable: false);

    return ThreadPostContent(html: html, trailingImageUrls: trailingImages);
  }
}

final RegExp _attachmentPattern = RegExp(r'\[attach\](\d+)\[/attach\]');

class ThreadDetailData {
  ThreadDetailData({
    required this.tid,
    required this.fid,
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
  final String subject;
  final String author;
  final int replies;
  final int views;
  final int currentPage;
  final int perPage;
  final List<ThreadPost> posts;

  /// Discuz 返回 replies 为回帖数，不含主楼，故这里使用 <= 保守判断
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
      fid: ParseUtils.asString(variables['fid']),
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
