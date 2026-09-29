import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_title_field_decoration.dart';
import 'package:y300/features/profile/presentation/blog/blog_body_input.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_settings.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:y300/l10n/app_localizations.dart';

class BlogEditorFields extends StatelessWidget {
  const BlogEditorFields({
    super.key,
    required this.state,
    required this.subject,
    required this.creatingCategory,
    required this.onOpenSettings,
    required this.onChanged,
    this.bodyMinLines = 12,
  });

  final BlogEditorState state;
  final TextEditingController subject;
  final bool creatingCategory;
  final VoidCallback? onOpenSettings;
  final int bodyMinLines;
  // Resolve edits against the latest draft, including before the next frame.
  final ValueChanged<BlogEditorDraft Function(BlogEditorDraft)> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final native = theme.y300NativeContent;
    final l10n = AppLocalizations.of(context);
    final readOnly =
        state.phase == BlogEditorPhase.unknown ||
        state.phase == BlogEditorPhase.applied;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('blog-editor-subject'),
          controller: subject,
          enabled: !state.busy,
          readOnly: readOnly,
          maxLines: null,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          style: theme.textTheme.titleLarge?.copyWith(
            color: native.itemTitle,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
          decoration: composerTitleFieldDecoration(
            context,
            hintText: l10n.profileBlogSubject,
          ).copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 16)),
          onChanged: (text) =>
              onChanged((draft) => draft.copyWith(subject: text)),
        ),
        const SizedBox(height: 4),
        BlogEditorSettingsSummary(
          state: state,
          creatingCategory: creatingCategory,
          onPressed: onOpenSettings,
        ),
        const SizedBox(height: 8),
        BlogBodyInput(
          html: state.draft.bodyHtml,
          enabled: !state.busy,
          readOnly: readOnly,
          minLines: bodyMinLines,
          onChanged: (html) =>
              onChanged((draft) => draft.copyWith(bodyHtml: html)),
        ),
      ],
    );
  }
}
