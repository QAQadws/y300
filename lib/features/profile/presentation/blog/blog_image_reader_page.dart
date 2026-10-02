import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_image_reader_capability.dart';
import 'package:y300/features/profile/presentation/blog/blog_image_reader_request.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/l10n/app_localizations.dart';

int _nextBlogImageSession = 0;

Future<void> openBlogImageReader(
  BuildContext context,
  WidgetRef ref, {
  required Object accountOwner,
  required ForumHtmlReadableImageSequence sequence,
  required ForumHtmlImageRequest image,
  required String cacheOwnerId,
  required String referer,
}) async {
  if (!context.mounted ||
      ModalRoute.of(context)?.isCurrent == false ||
      !identical(accountOwner, ref.read(blogMutationBusProvider))) {
    return;
  }
  final request = BlogImageReaderRequest.fromImage(
    sequence: sequence,
    image: image,
    cacheOwnerId: cacheOwnerId,
    sessionOwnerId: '${sequence.sourceId}:${_nextBlogImageSession++}',
    referer: referer,
    resolver: ref.read(forumImageRequestResolverProvider),
  );
  if (request == null) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => BlogImageReaderPage(
        request: request,
        referer: referer,
        accountOwner: accountOwner,
      ),
    ),
  );
}

class BlogImageReaderPage extends ConsumerStatefulWidget {
  const BlogImageReaderPage({
    super.key,
    required this.request,
    required this.referer,
    required this.accountOwner,
  });
  final BlogImageReaderRequest request;
  final String referer;
  final Object accountOwner;
  @override
  ConsumerState<BlogImageReaderPage> createState() =>
      _BlogImageReaderPageState();
}

class _BlogImageReaderPageState extends ConsumerState<BlogImageReaderPage> {
  bool _expired = false;
  @override
  void initState() {
    super.initState();
    ref.listenManual(blogMutationBusProvider, (_, owner) {
      if (!identical(owner, widget.accountOwner) && !_expired) {
        setState(() => _expired = true);
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_expired) {
      return Scaffold(
        appBar: AppBar(),
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
    return ImageReaderEngine(
      capability: BlogImageReaderCapability(
        request: widget.request,
        imageReferer: widget.referer,
        title: l10n.threadImageReaderTitle,
        displayLabel: l10n.threadImageDisplay,
        exportLabel: l10n.threadImageDownload,
      ),
    );
  }
}
