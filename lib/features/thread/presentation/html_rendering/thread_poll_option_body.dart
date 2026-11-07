import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';

import 'thread_html_image_reader_bridge.dart';

/// The poll retains its selection and command state. This adapter owns only
/// its option's actual HTML source and the existing shared image-reader bridge.
class ThreadPollOptionBody extends StatelessWidget {
  const ThreadPollOptionBody({
    required this.post,
    required this.option,
    required this.threadId,
    required this.imageReferer,
    required this.theme,
    required this.onOpenLink,
    this.onOpenImage,
    this.imageAnchorController,
    this.bodyPresentation,
    super.key,
  });

  final ThreadPost post;
  final ThreadPollOption option;
  final String threadId;
  final String imageReferer;
  final ForumHtmlThemeContext theme;
  final ValueChanged<String> onOpenLink;
  final void Function(ThreadPost, ThreadImageOpenRequest)? onOpenImage;
  final ForumHtmlImageAnchorController? imageAnchorController;
  final ForumHtmlBodyPresentation? bodyPresentation;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: Theme.of(context).textTheme.bodySmall,
    child: ForumHtmlContentView(
      html: option.contentHtml ?? '',
      sourceId:
          'thread:$threadId:post:${post.pid}:poll:${Uri.encodeComponent(option.id)}',
      imageCacheOwnerId: threadId,
      imageReferer: imageReferer,
      contentImageKind: ForumImageKind.threadInline,
      useSharedReaderFont: true,
      theme: theme,
      imageAnchorController: imageAnchorController,
      bodyPresentation: bodyPresentation,
      renderPreparer: const DefaultForumHtmlRenderPreparer(
        contentImageKind: ForumImageKind.threadInline,
      ),
      onOpenLink: onOpenLink,
      onOpenImage: onOpenImage == null
          ? null
          : (gallery, image) {
              final result = const ThreadHtmlImageReaderBridge()
                  .buildOpenRequest(
                    post: post,
                    threadId: threadId,
                    imageReferer: imageReferer,
                    sequence: gallery,
                    imageRequest: image,
                    pollOptionId: option.id,
                  );
              if (result.request case final request?) {
                onOpenImage?.call(post, request);
              }
            },
    ),
  );
}
