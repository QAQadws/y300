import '../contracts/thread_detail_models.dart';
import '../parsing/loose_json.dart';

final class ThreadDetailApiMapper {
  const ThreadDetailApiMapper();

  ThreadDetailData mapVariables(JsonMap variables, {required int page}) {
    final thread = LooseJson.map(variables['thread']);
    final perPage = LooseJson.integer(variables['ppp'], fallback: 20);
    return ThreadDetailData(
      tid: LooseJson.string(thread['tid']),
      fid: LooseJson.string(
        variables['fid'],
        fallback: LooseJson.string(thread['fid']),
      ),
      typeid: LooseJson.string(
        thread['typeid'],
        fallback: LooseJson.string(variables['typeid']),
      ),
      subject: LooseJson.string(thread['subject']),
      author: LooseJson.string(thread['author']),
      replies: LooseJson.integer(thread['replies']),
      views: LooseJson.integer(thread['views']),
      currentPage: page,
      perPage: perPage,
      posts: LooseJson.list(
        variables['postlist'],
      ).map((item) => mapPost(LooseJson.map(item))).toList(growable: false),
    );
  }

  ThreadPost mapPost(JsonMap json) {
    return ThreadPost(
      pid: LooseJson.string(json['pid']),
      author: LooseJson.string(json['author']),
      authorId: LooseJson.string(json['authorid']),
      message: LooseJson.string(json['message']),
      number: LooseJson.integer(json['number']),
      isFirst: LooseJson.string(json['first']) == '1',
      dateline: LooseJson.string(json['dateline']),
      editUrl: _nullableString(json['editUrl']),
      attachmentImages: _mapAttachments(json['attachments']),
    );
  }

  List<ForumPostAttachmentImage> _mapAttachments(dynamic value) {
    final attachments = LooseJson.map(value);
    return attachments.values
        .map(LooseJson.map)
        .where((item) => item.isNotEmpty)
        .map(
          (item) => ForumPostAttachmentImage(
            aid: LooseJson.string(item['aid']),
            url: LooseJson.string(item['url']),
            attachment: LooseJson.string(item['attachment']),
            filename: LooseJson.string(item['filename']),
            attachimg: LooseJson.string(item['attachimg']),
            ext: LooseJson.string(item['ext']),
          ),
        )
        .where((item) => item.attachment.trim().isNotEmpty)
        .toList(growable: false);
  }

  String? _nullableString(dynamic value) {
    final text = LooseJson.string(value).trim();
    return text.isEmpty ? null : text;
  }
}
