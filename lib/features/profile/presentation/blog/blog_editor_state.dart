import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

enum BlogEditorPhase {
  idle,
  preparing,
  ready,
  submitting,
  failed,
  unknown,
  applied,
  expired,
}

enum BlogEditorIssue {
  subjectRequired,
  bodyRequired,
  siteCategoryRequired,
  categoryUnavailable,
  newCategoryUnavailable,
  categoryConflict,
  feedUnavailable,
  visibilityUnavailable,
  commentsUnavailable,
  passwordRequired,
  targetNamesRequired,
  serverChanged,
}

/// Editable source values only. Reader typography and text conversion never
/// rewrite this input; the original HTML remains exact unless the user edits it.
@immutable
final class BlogEditorDraft {
  const BlogEditorDraft({
    this.subject = '',
    this.bodyHtml = '',
    this.tags = '',
    this.siteCategoryId = '0',
    this.personalCategoryId = '0',
    this.newPersonalCategory = '',
    this.publishFeed = false,
    this.visibility = UserBlogVisibility.public,
    this.commentsEnabled = true,
    this.targetNames = '',
    this.password = '',
  });

  factory BlogEditorDraft.from(UserBlogEditorPreparation form) =>
      BlogEditorDraft(
        subject: form.subject,
        bodyHtml: form.bodyHtml,
        tags: form.tags,
        siteCategoryId: form.siteCategoryId,
        personalCategoryId: form.personalCategoryId,
        publishFeed: form.publishFeed,
        visibility: form.visibility,
        commentsEnabled: form.commentsEnabled,
        targetNames: form.targetNames,
      );

  final String subject;
  final String bodyHtml;
  final String tags;
  final String siteCategoryId;
  final String personalCategoryId;
  final String newPersonalCategory;
  final bool publishFeed;
  final UserBlogVisibility visibility;
  final bool commentsEnabled;
  final String targetNames;
  // Only a newly entered password is held here. The saved password stays opaque.
  final String password;

  BlogEditorDraft copyWith({
    String? subject,
    String? bodyHtml,
    String? tags,
    String? siteCategoryId,
    String? personalCategoryId,
    String? newPersonalCategory,
    bool? publishFeed,
    UserBlogVisibility? visibility,
    bool? commentsEnabled,
    String? targetNames,
    String? password,
  }) => BlogEditorDraft(
    subject: subject ?? this.subject,
    bodyHtml: bodyHtml ?? this.bodyHtml,
    tags: tags ?? this.tags,
    siteCategoryId: siteCategoryId ?? this.siteCategoryId,
    personalCategoryId: personalCategoryId ?? this.personalCategoryId,
    newPersonalCategory: newPersonalCategory ?? this.newPersonalCategory,
    publishFeed: publishFeed ?? this.publishFeed,
    visibility: visibility ?? this.visibility,
    commentsEnabled: commentsEnabled ?? this.commentsEnabled,
    targetNames: targetNames ?? this.targetNames,
    password: password ?? this.password,
  );

  Object get _identity => (
    subject,
    bodyHtml,
    tags,
    siteCategoryId,
    personalCategoryId,
    newPersonalCategory,
    publishFeed,
    visibility,
    commentsEnabled,
    targetNames,
    password,
  );
  @override
  bool operator ==(Object other) =>
      other is BlogEditorDraft && _identity == other._identity;
  @override
  int get hashCode => _identity.hashCode;
}

/// Visible form metadata, deliberately excluding the opaque submission ticket.
@immutable
final class BlogEditorOptions {
  BlogEditorOptions.from(UserBlogEditorPreparation form)
    : siteCategories = List.unmodifiable(form.siteCategories),
      personalCategories = List.unmodifiable(form.personalCategories),
      siteCategoryRequired = form.siteCategoryRequired,
      canCreateCategory = form.canCreateCategory,
      canPublishFeed = form.canPublishFeed,
      visibility = form.visibility,
      commentsEnabled = form.commentsEnabled,
      availableVisibilities = List.unmodifiable(form.availableVisibilities),
      canEditComments = form.canEditComments,
      hasPassword = form.hasPassword,
      _targetNames = form.targetNames;

  final List<UserBlogCategory> siteCategories;
  final List<UserBlogCategory> personalCategories;
  final bool siteCategoryRequired;
  final bool canCreateCategory;
  final bool canPublishFeed;
  final UserBlogVisibility visibility;
  final bool commentsEnabled;
  final List<UserBlogVisibility> availableVisibilities;
  final bool canEditComments;
  final bool hasPassword;
  final String _targetNames;

  bool hasSameAccessCapabilities(BlogEditorOptions other) =>
      setEquals(
        availableVisibilities.toSet(),
        other.availableVisibilities.toSet(),
      ) &&
      canEditComments == other.canEditComments &&
      hasPassword == other.hasPassword;

  BlogEditorIssue? validate(BlogEditorDraft draft) {
    if (draft.subject.trim().isEmpty) return BlogEditorIssue.subjectRequired;
    if (draft.bodyHtml.trim().isEmpty) return BlogEditorIssue.bodyRequired;
    return validateSettings(draft);
  }

  BlogEditorIssue? validateSettings(BlogEditorDraft draft) {
    if (siteCategoryRequired && draft.siteCategoryId == '0') {
      return BlogEditorIssue.siteCategoryRequired;
    }
    if (!_contains(siteCategories, draft.siteCategoryId) ||
        !_contains(personalCategories, draft.personalCategoryId)) {
      return BlogEditorIssue.categoryUnavailable;
    }
    if (draft.newPersonalCategory.trim().isNotEmpty) {
      if (!canCreateCategory) return BlogEditorIssue.newCategoryUnavailable;
      if (draft.personalCategoryId != '0') {
        return BlogEditorIssue.categoryConflict;
      }
    }
    if (draft.publishFeed && !canPublishFeed) {
      return BlogEditorIssue.feedUnavailable;
    }
    final changesAccess =
        draft.visibility != visibility ||
        (draft.visibility == UserBlogVisibility.passwordProtected &&
            draft.password.trim().isNotEmpty) ||
        (draft.visibility == UserBlogVisibility.selectedFriends &&
            draft.targetNames != _targetNames);
    if (changesAccess && !availableVisibilities.contains(draft.visibility)) {
      return BlogEditorIssue.visibilityUnavailable;
    }
    if (draft.commentsEnabled != commentsEnabled && !canEditComments) {
      return BlogEditorIssue.commentsUnavailable;
    }
    if (draft.visibility == UserBlogVisibility.passwordProtected &&
        !(visibility == UserBlogVisibility.passwordProtected && hasPassword) &&
        draft.password.trim().isEmpty) {
      return BlogEditorIssue.passwordRequired;
    }
    if (draft.visibility == UserBlogVisibility.selectedFriends &&
        draft.targetNames.trim().isEmpty) {
      return BlogEditorIssue.targetNamesRequired;
    }
    return null;
  }

  bool _contains(List<UserBlogCategory> choices, String id) =>
      choices.any((category) => category.id == id) ||
      (choices.isEmpty && id == '0');
}

@immutable
final class BlogEditorState {
  const BlogEditorState({
    this.phase = BlogEditorPhase.idle,
    this.draft = const BlogEditorDraft(),
    this.original = const BlogEditorDraft(),
    this.serverVersion,
    this.options,
    this.needsReview = false,
    this.failure,
    this.issue,
  });
  final BlogEditorPhase phase;
  final BlogEditorDraft draft;
  final BlogEditorDraft original;
  final BlogEditorDraft? serverVersion;
  final BlogEditorOptions? options;
  final bool needsReview;
  final Object? failure;
  final BlogEditorIssue? issue;
  bool get busy =>
      phase == BlogEditorPhase.preparing || phase == BlogEditorPhase.submitting;
  bool get dirty => draft != original;
  bool get canSubmit => phase == BlogEditorPhase.ready && !needsReview;
}
