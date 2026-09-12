import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/profile/presentation/blog/blog_body_input.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class BlogEditorFields extends StatelessWidget {
  const BlogEditorFields({
    super.key,
    required this.state,
    required this.subject,
    required this.tags,
    required this.categoryName,
    required this.creatingCategory,
    required this.onCreateCategory,
    required this.onChanged,
    this.categoryNameRequired = false,
  });
  final BlogEditorState state;
  final TextEditingController subject;
  final TextEditingController tags;
  final TextEditingController categoryName;
  final bool creatingCategory;
  final bool categoryNameRequired;
  final ValueChanged<bool> onCreateCategory;
  // Resolve edits against the latest draft, including before the next frame.
  final ValueChanged<BlogEditorDraft Function(BlogEditorDraft)> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final native = Theme.of(context).y300NativeContent;
    final draft = state.draft;
    final options = state.options!;
    final enabled = !state.busy;
    final readOnly =
        state.phase == BlogEditorPhase.unknown ||
        state.phase == BlogEditorPhase.applied;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('blog-editor-subject'),
          controller: subject,
          enabled: enabled,
          readOnly: readOnly,
          maxLines: null,
          keyboardType: TextInputType.text,
          style: TextStyle(color: native.body),
          decoration: InputDecoration(labelText: l10n.profileBlogSubject),
          onChanged: (text) =>
              onChanged((draft) => draft.copyWith(subject: text)),
        ),
        const SizedBox(height: 12),
        BlogBodyInput(
          html: draft.bodyHtml,
          enabled: enabled,
          readOnly: readOnly,
          onChanged: (html) =>
              onChanged((draft) => draft.copyWith(bodyHtml: html)),
        ),
        const SizedBox(height: 16),
        if (options.siteCategories.isNotEmpty) ...[
          _CategoryField(
            fieldKey: const Key('blog-editor-site-category'),
            label: l10n.profileBlogSiteCategory,
            choices: options.siteCategories,
            selected: draft.siteCategoryId,
            onChanged: enabled && !readOnly
                ? (id) =>
                      onChanged((draft) => draft.copyWith(siteCategoryId: id))
                : null,
          ),
          const SizedBox(height: 12),
        ],
        _CategoryField(
          fieldKey: const Key('blog-editor-personal-category'),
          label: l10n.profileBlogPersonalCategory,
          choices: options.personalCategories,
          selected: creatingCategory ? 'new' : draft.personalCategoryId,
          includeNew: options.canCreateCategory || creatingCategory,
          allowNew: options.canCreateCategory,
          onChanged: enabled && !readOnly
              ? (id) {
                  onCreateCategory(id == 'new');
                  onChanged(
                    (draft) => draft.copyWith(
                      personalCategoryId: id == 'new' ? '0' : id,
                      newPersonalCategory: id == 'new' ? categoryName.text : '',
                    ),
                  );
                }
              : null,
        ),
        if (creatingCategory) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('blog-editor-category-name'),
            controller: categoryName,
            enabled: enabled,
            readOnly: readOnly,
            style: TextStyle(color: native.body),
            decoration: InputDecoration(
              labelText: l10n.profileBlogNewCategoryName,
              errorText: categoryNameRequired
                  ? l10n.profileBlogNewCategoryNameRequired
                  : null,
            ),
            onChanged: (text) =>
                onChanged((draft) => draft.copyWith(newPersonalCategory: text)),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const Key('blog-editor-tags'),
          controller: tags,
          enabled: enabled,
          readOnly: readOnly,
          style: TextStyle(color: native.body),
          decoration: InputDecoration(labelText: l10n.profileBlogTags),
          onChanged: (text) => onChanged((draft) => draft.copyWith(tags: text)),
        ),
        if (options.canPublishFeed || draft.publishFeed)
          CheckboxListTile(
            key: const Key('blog-editor-publish-feed'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.profileBlogPublishFeed,
              style: TextStyle(color: native.body),
            ),
            value: draft.publishFeed,
            onChanged: enabled && !readOnly
                ? (value) {
                    if (value == true && !options.canPublishFeed) return;
                    onChanged(
                      (draft) => draft.copyWith(publishFeed: value ?? false),
                    );
                  }
                : null,
          ),
        const SizedBox(height: 16),
        Text(
          l10n.profileBlogAccessPolicy(_visibility(l10n, options.visibility)),
          style: TextStyle(color: native.body),
        ),
        const SizedBox(height: 4),
        Text(
          options.commentsEnabled
              ? l10n.profileBlogCommentsAllowed
              : l10n.profileBlogCommentsClosed,
          style: TextStyle(color: native.supportingText),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.profileBlogPolicyNotice,
          style: TextStyle(color: native.supportingText),
        ),
      ],
    );
  }
}

class _CategoryField extends StatelessWidget {
  const _CategoryField({
    required this.fieldKey,
    required this.label,
    required this.choices,
    required this.selected,
    required this.onChanged,
    this.includeNew = false,
    this.allowNew = false,
  });
  final Key fieldKey;
  final String label;
  final List<UserBlogCategory> choices;
  final String selected;
  final ValueChanged<String>? onChanged;
  final bool includeNew;
  final bool allowNew;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = <String, String>{
      if (choices.isEmpty) '0': l10n.profileBlogNoCategory,
      for (final category in choices)
        category.id: category.id == '0'
            ? l10n.profileBlogNoCategory
            : category.name,
      if (includeNew) 'new': l10n.profileBlogNewCategory,
    };
    return KeyedSubtree(
      key: fieldKey,
      child: DropdownButtonFormField<String>(
        key: ValueKey((
          fieldKey,
          selected,
          Object.hashAll(labels.entries.map((e) => (e.key, e.value))),
        )),
        initialValue: labels.containsKey(selected) ? selected : null,
        decoration: InputDecoration(labelText: label),
        isExpanded: true,
        hint: Text(l10n.profileBlogChooseCategory),
        items: [
          for (final entry in labels.entries)
            DropdownMenuItem(
              value: entry.key,
              enabled: entry.key != 'new' || allowNew,
              child: Text(
                entry.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged == null
            ? null
            : (value) {
                if (value != null) onChanged!(value);
              },
      ),
    );
  }
}

class BlogEditorServerMetadata extends StatelessWidget {
  const BlogEditorServerMetadata({
    super.key,
    required this.draft,
    required this.options,
  });
  final BlogEditorDraft draft;
  final BlogEditorOptions options;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String category(List<UserBlogCategory> choices, String id) => id == '0'
        ? l10n.profileBlogNoCategory
        : choices.where((choice) => choice.id == id).firstOrNull?.name ?? id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.profileBlogServerCategories(
            category(options.siteCategories, draft.siteCategoryId),
            category(options.personalCategories, draft.personalCategoryId),
          ),
        ),
        Text(l10n.profileBlogServerTags(draft.tags)),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.profileBlogPublishFeed),
          value: draft.publishFeed,
          onChanged: null,
        ),
      ],
    );
  }
}

String _visibility(AppLocalizations l10n, UserBlogVisibility value) =>
    switch (value) {
      UserBlogVisibility.public => l10n.profileBlogVisibilityPublic,
      UserBlogVisibility.friends => l10n.profileBlogVisibilityFriends,
      UserBlogVisibility.selectedFriends => l10n.profileBlogVisibilitySelected,
      UserBlogVisibility.private => l10n.profileBlogVisibilityPrivate,
      UserBlogVisibility.passwordProtected =>
        l10n.profileBlogVisibilityPassword,
    };
