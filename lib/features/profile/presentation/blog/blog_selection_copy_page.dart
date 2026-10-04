import 'package:y300/app/content_rendering/native_forum_html_render_theme_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_link_navigation.dart';
import 'package:y300/features/profile/presentation/blog/blog_image_reader_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_selection_copy_page.dart';

class BlogSelectionCopyPage extends ConsumerStatefulWidget {
  const BlogSelectionCopyPage({
    super.key,
    required this.displayHtml,
    required this.accountOwner,
    required this.sourceId,
    required this.cacheOwnerId,
    required this.imageReferer,
    required this.linkBaseUri,
  });

  final String displayHtml;
  final Object accountOwner;
  final String sourceId;
  final String cacheOwnerId;
  final String imageReferer;
  final Uri? linkBaseUri;

  @override
  ConsumerState<BlogSelectionCopyPage> createState() =>
      _BlogSelectionCopyPageState();
}

class _BlogSelectionCopyPageState extends ConsumerState<BlogSelectionCopyPage> {
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(blogMutationBusProvider, (_, owner) {
      // Once invalidated, returning to the same account cannot revive old text.
      if (!identical(owner, widget.accountOwner) && !_expired) {
        setState(() => _expired = true);
      }
    }, fireImmediately: true);
  }

  bool get _canInteract =>
      mounted &&
      !_expired &&
      identical(ref.read(blogMutationBusProvider), widget.accountOwner) &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_expired) {
      return Scaffold(
        key: const Key('blog-selection-copy-page'),
        appBar: AppBar(title: Text(l10n.threadSelectionCopyTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.profileBlogCommentSessionChanged,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return ForumContentSelectionCopyPage(
      key: const Key('blog-selection-copy-page'),
      title: l10n.threadSelectionCopyTitle,
      bodyKey: const Key('blog-selection-copy-body'),
      child: ForumHtmlContentView(
        html: widget.displayHtml,
        sourceId: widget.sourceId,
        imageReferer: widget.imageReferer,
        imageCacheOwnerId: widget.cacheOwnerId,
        contentImageKind: ForumImageKind.blogInline,
        linkBaseUri: widget.linkBaseUri,
        theme: const ForumHtmlRenderThemeFactory().fromNativeTheme(
          theme: Theme.of(context),
        ),
        onOpenLink: (url) {
          if (!_canInteract) return;
          openBlogContentLink(context, ref, url, baseUri: widget.linkBaseUri);
        },
        onOpenImage: (sequence, image) {
          if (!_canInteract) return;
          openBlogImageReader(
            context,
            ref,
            accountOwner: widget.accountOwner,
            sequence: sequence,
            image: image,
            cacheOwnerId: widget.cacheOwnerId,
            referer: widget.imageReferer,
          );
        },
      ),
    );
  }
}
