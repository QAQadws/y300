import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_access_fields.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class BlogEditorSettingsFields extends StatelessWidget {
  const BlogEditorSettingsFields({
    super.key,
    required this.state,
    required this.tags,
    required this.categoryName,
    required this.password,
    required this.targetNames,
    required this.creatingCategory,
    required this.onCreateCategory,
    required this.onChanged,
    this.locked = false,
    this.categoryNameRequired = false,
  });

  final BlogEditorState state;
  final bool locked;
  final TextEditingController tags;
  final TextEditingController categoryName;
  final TextEditingController password;
  final TextEditingController targetNames;
  final bool creatingCategory;
  final bool categoryNameRequired;
  final ValueChanged<bool> onCreateCategory;
  // Resolve edits against the latest draft, including before the next frame.
  final ValueChanged<BlogEditorDraft Function(BlogEditorDraft)> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final native = theme.y300NativeContent;
    final draft = state.draft;
    final options = state.options!;
    final enabled = !state.busy;
    final readOnly =
        locked ||
        {
          BlogEditorPhase.unknown,
          BlogEditorPhase.applied,
          BlogEditorPhase.expired,
        }.contains(state.phase);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            style: theme.textTheme.bodyMedium?.copyWith(color: native.body),
            decoration:
                _settingDecoration(
                  context,
                  label: l10n.profileBlogNewCategoryName,
                ).copyWith(
                  errorText: categoryNameRequired
                      ? l10n.profileBlogNewCategoryNameRequired
                      : null,
                  errorMaxLines: 3,
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
          style: theme.textTheme.bodyMedium?.copyWith(color: native.body),
          decoration: _settingDecoration(context, label: l10n.profileBlogTags),
          onChanged: (text) => onChanged((draft) => draft.copyWith(tags: text)),
        ),
        if (options.canPublishFeed || draft.publishFeed) ...[
          const SizedBox(height: 4),
          SwitchListTile(
            key: const Key('blog-editor-publish-feed'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              l10n.profileBlogPublishFeed,
              style: theme.textTheme.bodyMedium?.copyWith(color: native.body),
            ),
            activeThumbColor: native.author,
            activeTrackColor: native.selectionBackground,
            value: draft.publishFeed,
            onChanged: enabled && !readOnly
                ? (value) {
                    if (value && !options.canPublishFeed) return;
                    onChanged((draft) => draft.copyWith(publishFeed: value));
                  }
                : null,
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: native.subtleStateLayer),
        ),
        BlogEditorAccessFields(
          state: state,
          locked: locked,
          password: password,
          targetNames: targetNames,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class BlogEditorSettingsSummary extends StatelessWidget {
  const BlogEditorSettingsSummary({
    super.key,
    required this.state,
    required this.creatingCategory,
  });

  final BlogEditorState state;
  final bool creatingCategory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final native = theme.y300NativeContent;
    final options = state.options!;
    final draft = state.draft;
    final newCategory = draft.newPersonalCategory.trim();
    final category = creatingCategory
        ? newCategory.isEmpty
              ? l10n.profileBlogNewCategory
              : newCategory
        : _category(l10n, options.personalCategories, draft.personalCategoryId);
    final details = [
      blogVisibilityLabel(l10n, draft.visibility),
      draft.commentsEnabled
          ? l10n.profileBlogCommentsAllowed
          : l10n.profileBlogCommentsClosed,
      if (options.siteCategoryRequired && draft.siteCategoryId == '0')
        l10n.profileBlogSiteCategoryRequired
      else if (draft.siteCategoryId != '0')
        _category(l10n, options.siteCategories, draft.siteCategoryId),
      if (draft.tags.trim().isNotEmpty)
        l10n.profileBlogServerTags(draft.tags.trim()),
    ].join(' · ');
    return Padding(
      key: const Key('blog-editor-settings-summary'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        '$category · $details',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: native.supportingText,
          height: 1.4,
        ),
      ),
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
    final theme = Theme.of(context);
    final native = theme.y300NativeContent;
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
          Object.hashAll(
            labels.entries.map((entry) => (entry.key, entry.value)),
          ),
        )),
        initialValue: labels.containsKey(selected) ? selected : null,
        decoration: _settingDecoration(context, label: label),
        style: theme.textTheme.bodyMedium?.copyWith(color: native.body),
        iconEnabledColor: native.supportingText,
        iconDisabledColor: native.disabled,
        dropdownColor: native.card,
        isExpanded: true,
        itemHeight: null,
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
    final theme = Theme.of(context);
    final native = theme.y300NativeContent;
    return DefaultTextStyle.merge(
      style: TextStyle(color: native.body),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.profileBlogServerCategories(
              _category(l10n, options.siteCategories, draft.siteCategoryId),
              _category(
                l10n,
                options.personalCategories,
                draft.personalCategoryId,
              ),
            ),
          ),
          Text(l10n.profileBlogServerTags(draft.tags)),
          Text(
            l10n.profileBlogAccessPolicy(
              blogVisibilityLabel(l10n, draft.visibility),
            ),
          ),
          Text(
            draft.commentsEnabled
                ? l10n.profileBlogCommentsAllowed
                : l10n.profileBlogCommentsClosed,
          ),
          if (draft.visibility == UserBlogVisibility.selectedFriends)
            Text('${l10n.profileBlogTargetNames}：${draft.targetNames}'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.profileBlogPublishFeed),
            value: draft.publishFeed,
            onChanged: null,
          ),
        ],
      ),
    );
  }
}

InputDecoration _settingDecoration(
  BuildContext context, {
  required String label,
}) {
  final native = Theme.of(context).y300NativeContent;
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: native.supportingText),
    floatingLabelStyle: TextStyle(color: native.author),
    isDense: true,
    filled: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

String _category(
  AppLocalizations l10n,
  List<UserBlogCategory> choices,
  String id,
) => id == '0'
    ? l10n.profileBlogNoCategory
    : choices.where((choice) => choice.id == id).firstOrNull?.name ?? id;
