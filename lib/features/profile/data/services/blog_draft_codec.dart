import 'dart:convert';
import 'package:y300/features/profile/domain/models/blog_draft_snapshot.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Explicit allowlist: passwords, tokens and local file paths cannot leak here.
final class BlogDraftCodec {
  const BlogDraftCodec();

  String encode(BlogDraftSnapshot draft) => jsonEncode({
    'version': 1,
    'accountId': draft.accountId,
    'updatedAt': draft.updatedAt.toIso8601String(),
    'subject': draft.subject,
    'bodyHtml': draft.bodyHtml,
    'tags': draft.tags,
    'siteCategoryId': draft.siteCategoryId,
    'personalCategoryId': draft.personalCategoryId,
    'newPersonalCategory': draft.newPersonalCategory,
    'creatingCategory': draft.creatingCategory,
    'publishFeed': draft.publishFeed,
    'visibility': draft.visibility.name,
    'commentsEnabled': draft.commentsEnabled,
    'targetNames': draft.targetNames,
    'pendingSubmission': draft.pendingSubmission,
    'images': [
      for (final image in draft.images)
        {'picId': image.picId, 'originalUri': image.originalUri.toString()},
    ],
  });

  BlogDraftSnapshot decode(String source, {required String accountId}) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['accountId'] != accountId ||
        !RegExp(r'^[1-9]\d*$').hasMatch(accountId)) {
      throw const FormatException('blog_draft_identity_invalid');
    }
    String text(String key) => data[key] as String;
    bool flag(String key) => data[key] as bool;
    final images = <BlogDraftImage>[];
    for (final item in data['images'] as List) {
      final id = item['picId'] as String;
      final uri = Uri.parse(item['originalUri'] as String);
      if (!RegExp(r'^[1-9]\d*$').hasMatch(id) ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.fragment.isNotEmpty) {
        throw const FormatException('blog_draft_image_invalid');
      }
      images.add(BlogDraftImage(picId: id, originalUri: uri));
    }
    return BlogDraftSnapshot(
      accountId: accountId,
      updatedAt: DateTime.parse(text('updatedAt')),
      subject: text('subject'),
      bodyHtml: text('bodyHtml'),
      tags: text('tags'),
      siteCategoryId: text('siteCategoryId'),
      personalCategoryId: text('personalCategoryId'),
      newPersonalCategory: text('newPersonalCategory'),
      creatingCategory: flag('creatingCategory'),
      publishFeed: flag('publishFeed'),
      visibility: UserBlogVisibility.values.byName(text('visibility')),
      commentsEnabled: flag('commentsEnabled'),
      targetNames: text('targetNames'),
      images: List.unmodifiable(images),
      pendingSubmission: flag('pendingSubmission'),
    );
  }
}
