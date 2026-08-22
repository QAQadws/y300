import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';

final class ThreadDetailApiMapper {
  const ThreadDetailApiMapper();

  ThreadDetailData mapVariables(JsonMap variables, {required int page}) {
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
      posts: ParseUtils.asList(variables['postlist'])
          .map((item) => mapPost(ParseUtils.asMap(item)))
          .toList(growable: false),
    );
  }

  ThreadPost mapPost(JsonMap json) {
    return ThreadPost(
      pid: ParseUtils.asString(json['pid']),
      author: ParseUtils.asString(json['author']),
      authorId: ParseUtils.asString(json['authorid']),
      message: ParseUtils.asString(json['message']),
      number: ParseUtils.asInt(json['number']),
      isFirst: ParseUtils.asString(json['first']) == '1',
      dateline: ParseUtils.asString(json['dateline']),
      editUrl: _nullableString(json['editUrl']),
      attachmentImages: _mapAttachments(json['attachments']),
    );
  }

  List<ForumPostAttachmentImage> _mapAttachments(dynamic value) {
    final attachments = ParseUtils.asMap(value);
    return attachments.values
        .map(ParseUtils.asMap)
        .where((item) => item.isNotEmpty)
        .map(
          (item) => ForumPostAttachmentImage(
            aid: ParseUtils.asString(item['aid']),
            url: ParseUtils.asString(item['url']),
            attachment: ParseUtils.asString(item['attachment']),
            filename: ParseUtils.asString(item['filename']),
            attachimg: ParseUtils.asString(item['attachimg']),
            ext: ParseUtils.asString(item['ext']),
          ),
        )
        .where((item) => item.attachment.trim().isNotEmpty)
        .toList(growable: false);
  }

  String? _nullableString(dynamic value) {
    final text = ParseUtils.asString(value).trim();
    return text.isEmpty ? null : text;
  }
}
