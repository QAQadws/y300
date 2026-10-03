import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html;
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_sticker_text_controller.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_sticker_embed_builder.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_image.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_projection.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_projection_provider.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

StickerItem blogCommentSticker(UserBlogCommentSmiley smiley) => StickerItem(
  code: smiley.code,
  rawCodePattern: smiley.code,
  imagePath: smiley.imageUri.path,
  imageUrl: smiley.imageUri.toString(),
  cacheKey: smiley.imageUri.toString(),
);

/// Comments remain lossless source text; only source-proved smileys are embeds.
class BlogCommentInput extends StatelessWidget {
  const BlogCommentInput({super.key, required this.controller});

  final ComposerStickerTextController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final native = theme.y300NativeContent;
    final style = theme.textTheme.bodyLarge!.copyWith(
      color: native.body,
      height: 1.6,
    );
    DefaultTextBlockStyle blockStyle(Color color) => DefaultTextBlockStyle(
      style.copyWith(color: color),
      const HorizontalSpacing(0, 0),
      const VerticalSpacing(0, 0),
      const VerticalSpacing(0, 0),
      null,
    );
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Semantics(
        label: AppLocalizations.of(context).profileBlogCommentContent,
        child: QuillEditor.basic(
          key: const Key('blog-comment-input'),
          controller: controller.quill,
          focusNode: controller.focusNode,
          scrollController: controller.scrollController,
          config: QuillEditorConfig(
            expands: true,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            placeholder: AppLocalizations.of(context).profileBlogCommentContent,
            scrollPhysics: const ClampingScrollPhysics(),
            // This public hook prevents rich-format shortcuts in plain input.
            // ignore: experimental_member_use
            onKeyPressed: controller.handleKeyPressed,
            customStyles: DefaultStyles(
              paragraph: blockStyle(native.body),
              placeHolder: blockStyle(native.supportingText),
            ),
            embedBuilders: [
              ComposerQuillStickerEmbedBuilder(
                stickers: controller.stickers,
                fixedSize:
                    MediaQuery.textScalerOf(
                      context,
                    ).scale(style.fontSize ?? 16) *
                    1.25,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kept outside the scrolling document so actions stay above the keyboard.
class BlogCommentToolbar extends StatelessWidget {
  const BlogCommentToolbar({
    super.key,
    required this.actionLabel,
    required this.actionKey,
    required this.actionIcon,
    this.onAction,
    this.showSmiley = true,
    this.onSmiley,
    this.onOpenWeb,
  });

  final String actionLabel;
  final Key actionKey;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final bool showSmiley;
  final VoidCallback? onSmiley;
  final VoidCallback? onOpenWeb;

  @override
  Widget build(BuildContext context) {
    final native = Theme.of(context).y300NativeContent;
    final l10n = AppLocalizations.of(context);
    return Material(
      color: native.card,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: native.subtleStateLayer)),
          ),
          child: Padding(
            key: const Key('blog-comment-toolbar'),
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(
              children: [
                if (showSmiley)
                  IconButton(
                    key: const Key('blog-comment-smiley'),
                    tooltip: l10n.composerSticker,
                    onPressed: onSmiley,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                  ),
                if (onOpenWeb != null)
                  IconButton(
                    key: const Key('blog-comment-open-web'),
                    tooltip: l10n.profileBlogOpenWeb,
                    onPressed: onOpenWeb,
                    icon: const Icon(Icons.open_in_browser_outlined),
                  ),
                const Spacer(),
                Flexible(
                  flex: 0,
                  child: FilledButton.icon(
                    key: actionKey,
                    onPressed: onAction,
                    icon: Icon(actionIcon, size: 20),
                    label: Text(actionLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Display context only: Discuz adds its own quote using the submitted cid.
class BlogCommentReplyContext extends ConsumerWidget {
  const BlogCommentReplyContext({super.key, required this.comment});

  final UserBlogComment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final native = Theme.of(context).y300NativeContent;
    final display = watchBlogDisplayText(
      ref,
      BlogContentSource.comment(comment),
    );
    final fragment = html.parseFragment(display.html(comment.bodyHtml));
    // The server quotes the target's own words, excluding earlier quotes.
    for (final node in fragment.querySelectorAll(
      'blockquote, .quote, script, style',
    )) {
      node.remove();
    }
    final excerpt = (fragment.text ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DecoratedBox(
        key: const Key('blog-comment-reply-context'),
        decoration: BoxDecoration(
          color: native.subtleStateLayer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(
                  context,
                ).profileBlogCommentReplyTo(comment.authorName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge!.copyWith(color: native.author),
              ),
              if (excerpt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: native.supportingText),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class BlogCommentSmileySheet extends StatelessWidget {
  const BlogCommentSmileySheet({super.key, required this.smilies});

  final List<UserBlogCommentSmiley> smilies;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The picker replaces the keyboard. Its dismissal animation may still
    // report the previous IME inset, which must not shrink this sheet again.
    final available = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: (available * 0.48).clamp(0.0, 360.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.composerSticker,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.commonClose,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                key: const Key('blog-comment-smiley-picker'),
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 64,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: smilies.length,
                itemBuilder: (context, index) {
                  final item = smilies[index];
                  return IconButton(
                    key: Key('blog-comment-smiley-${item.index}'),
                    tooltip: l10n.profileBlogCommentSmileyLabel(item.index),
                    onPressed: () => Navigator.pop(context, item),
                    icon: ComposerStickerImage(
                      sticker: blogCommentSticker(item),
                      width: 32,
                      height: 32,
                      placeholder: const Icon(Icons.mood_outlined),
                      errorPlaceholder: const Icon(Icons.mood_outlined),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
