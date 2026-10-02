import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/profile/presentation/blog/blog_rich_text_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_rich_text_embeds.dart';
import 'package:y300/l10n/app_localizations.dart';

class BlogBodyInput extends StatelessWidget {
  const BlogBodyInput({
    super.key,
    required this.controller,
    required this.enabled,
    required this.readOnly,
    this.imagePreviews = const {},
    this.minLines = 8,
  });
  final BlogRichTextController controller;
  final bool enabled;
  final bool readOnly;
  final Map<String, String> imagePreviews;
  final int minLines;
  @override
  Widget build(BuildContext context) {
    final native = Theme.of(context).y300NativeContent;
    controller.quill.readOnly = !enabled || readOnly;
    DefaultTextBlockStyle style(Color color) => DefaultTextBlockStyle(
      Theme.of(
        context,
      ).textTheme.bodyMedium!.copyWith(color: color, fontSize: 16, height: 1.6),
      const HorizontalSpacing(0, 0),
      const VerticalSpacing(0, 0),
      const VerticalSpacing(0, 0),
      null,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: minLines * MediaQuery.textScalerOf(context).scale(16) * 1.6,
      ),
      child: QuillEditor.basic(
        key: const Key('blog-editor-body'),
        controller: controller.quill,
        focusNode: controller.focusNode,
        scrollController: controller.scrollController,
        config: QuillEditorConfig(
          scrollable: false,
          padding: const EdgeInsets.symmetric(vertical: 12),
          placeholder: AppLocalizations.of(context).profileBlogStartWriting,
          showCursor: enabled && !readOnly,
          customStyles: DefaultStyles(
            paragraph: style(native.body),
            placeHolder: style(native.supportingText),
          ),
          embedBuilders: [
            BlogImageEmbedBuilder(previews: imagePreviews),
            const BlogHtmlEmbedBuilder(),
          ],
        ),
      ),
    );
  }
}
