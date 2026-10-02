import 'package:html/parser.dart' as html;
import 'package:y300/features/profile/domain/models/blog_draft_snapshot.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';

BlogEditorDraft restoreBlogDraft(BlogDraftSnapshot value) => BlogEditorDraft(
  subject: value.subject,
  bodyHtml: value.bodyHtml,
  tags: value.tags,
  siteCategoryId: value.siteCategoryId,
  personalCategoryId: value.personalCategoryId,
  newPersonalCategory: value.newPersonalCategory,
  publishFeed: value.publishFeed,
  visibility: value.visibility,
  commentsEnabled: value.commentsEnabled,
  targetNames: value.targetNames,
);

BlogDraftSnapshot snapshotBlogDraft({
  required String accountId,
  required BlogEditorDraft draft,
  required DateTime updatedAt,
  required bool creatingCategory,
  required List<BlogDraftImage> images,
  required bool pendingSubmission,
}) {
  final sources = html
      .parseFragment(draft.bodyHtml)
      .querySelectorAll('img[src]')
      .map((node) => node.attributes['src'])
      .toSet();
  return BlogDraftSnapshot(
    accountId: accountId,
    updatedAt: updatedAt,
    subject: draft.subject,
    bodyHtml: draft.bodyHtml,
    tags: draft.tags,
    siteCategoryId: draft.siteCategoryId,
    personalCategoryId: draft.personalCategoryId,
    newPersonalCategory: draft.newPersonalCategory,
    creatingCategory: creatingCategory,
    publishFeed: draft.publishFeed,
    visibility: draft.visibility,
    commentsEnabled: draft.commentsEnabled,
    targetNames: draft.targetNames,
    pendingSubmission: pendingSubmission,
    images: List.unmodifiable(
      images.where((image) => sources.contains(image.originalUri.toString())),
    ),
  );
}
