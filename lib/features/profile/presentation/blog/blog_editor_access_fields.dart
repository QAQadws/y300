import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class BlogEditorAccessFields extends StatelessWidget {
  const BlogEditorAccessFields({
    super.key,
    required this.state,
    required this.password,
    required this.targetNames,
    required this.onChanged,
  });
  final BlogEditorState state;
  final TextEditingController password;
  final TextEditingController targetNames;
  final ValueChanged<BlogEditorDraft Function(BlogEditorDraft)> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final native = theme.y300NativeContent;
    final draft = state.draft;
    final options = state.options!;
    final enabled = !state.busy;
    final readOnly = {
      BlogEditorPhase.unknown,
      BlogEditorPhase.applied,
      BlogEditorPhase.expired,
    }.contains(state.phase);
    final canEditAccess = options.availableVisibilities.contains(
      draft.visibility,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: const Key('blog-editor-visibility'),
          child: DropdownButtonFormField<UserBlogVisibility>(
            key: ValueKey((
              draft.visibility,
              Object.hashAll(options.availableVisibilities),
            )),
            initialValue: draft.visibility,
            decoration:
                _settingDecoration(
                  context,
                  label: l10n.profileBlogAccessScope,
                ).copyWith(
                  prefixIcon: Icon(_visibilityIcon(draft.visibility), size: 20),
                  errorText:
                      state.issue == BlogEditorIssue.visibilityUnavailable
                      ? l10n.profileBlogVisibilityUnavailable
                      : null,
                  errorMaxLines: 3,
                ),
            style: theme.textTheme.bodyMedium?.copyWith(color: native.body),
            dropdownColor: native.card,
            isExpanded: true,
            itemHeight: null,
            items: [
              for (final visibility in {
                ...options.availableVisibilities,
                draft.visibility,
              })
                DropdownMenuItem(
                  value: visibility,
                  enabled: options.availableVisibilities.contains(visibility),
                  child: Text(
                    blogVisibilityLabel(l10n, visibility),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged:
                enabled && !readOnly && options.availableVisibilities.isNotEmpty
                ? (visibility) {
                    if (visibility != null) {
                      onChanged(
                        (draft) => draft.copyWith(visibility: visibility),
                      );
                    }
                  }
                : null,
          ),
        ),
        if (draft.visibility == UserBlogVisibility.passwordProtected) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('blog-editor-password'),
            controller: password,
            enabled: enabled,
            readOnly: readOnly || !canEditAccess,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.visiblePassword,
            decoration:
                _settingDecoration(
                  context,
                  label: l10n.profileBlogPassword,
                ).copyWith(
                  helperText: options.hasPassword
                      ? l10n.profileBlogKeepPassword
                      : null,
                  helperMaxLines: 3,
                  errorText: state.issue == BlogEditorIssue.passwordRequired
                      ? l10n.profileBlogPasswordRequired
                      : null,
                  errorMaxLines: 3,
                ),
            onChanged: (value) =>
                onChanged((draft) => draft.copyWith(password: value)),
          ),
        ],
        if (draft.visibility == UserBlogVisibility.selectedFriends) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('blog-editor-target-names'),
            controller: targetNames,
            enabled: enabled,
            readOnly: readOnly || !canEditAccess,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration:
                _settingDecoration(
                  context,
                  label: l10n.profileBlogTargetNames,
                ).copyWith(
                  helperText: l10n.profileBlogTargetNamesHint,
                  helperMaxLines: 3,
                  errorText: state.issue == BlogEditorIssue.targetNamesRequired
                      ? l10n.profileBlogTargetNamesRequired
                      : null,
                  errorMaxLines: 3,
                ),
            onChanged: (value) =>
                onChanged((draft) => draft.copyWith(targetNames: value)),
          ),
        ],
        const SizedBox(height: 4),
        SwitchListTile(
          key: const Key('blog-editor-comments-enabled'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            l10n.profileBlogCommentsAllowed,
            style: theme.textTheme.bodyMedium?.copyWith(color: native.body),
          ),
          value: draft.commentsEnabled,
          onChanged: enabled && !readOnly && options.canEditComments
              ? (value) =>
                    onChanged((draft) => draft.copyWith(commentsEnabled: value))
              : null,
          activeThumbColor: native.author,
          activeTrackColor: native.selectionBackground,
        ),
      ],
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

String blogVisibilityLabel(AppLocalizations l10n, UserBlogVisibility value) =>
    switch (value) {
      UserBlogVisibility.public => l10n.profileBlogVisibilityPublic,
      UserBlogVisibility.friends => l10n.profileBlogVisibilityFriends,
      UserBlogVisibility.selectedFriends => l10n.profileBlogVisibilitySelected,
      UserBlogVisibility.private => l10n.profileBlogVisibilityPrivate,
      UserBlogVisibility.passwordProtected =>
        l10n.profileBlogVisibilityPassword,
    };

IconData _visibilityIcon(UserBlogVisibility value) => switch (value) {
  UserBlogVisibility.public => Icons.public,
  UserBlogVisibility.friends ||
  UserBlogVisibility.selectedFriends => Icons.people_outline,
  UserBlogVisibility.private ||
  UserBlogVisibility.passwordProtected => Icons.lock_outline,
};
