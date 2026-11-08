import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// A stable thumbnail slot, including when its lazy parent is recreated.
class ThreadPollOptionImageView extends ConsumerStatefulWidget {
  const ThreadPollOptionImageView({
    super.key,
    required this.image,
    required this.ownerId,
    required this.backgroundColor,
    required this.foregroundColor,
    this.referer,
  });

  final ThreadPollOptionImage image;
  final String ownerId;
  final String? referer;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  ConsumerState<ThreadPollOptionImageView> createState() =>
      _ThreadPollOptionImageViewState();
}

class _ThreadPollOptionImageViewState
    extends ConsumerState<ThreadPollOptionImageView> {
  static const _extent = 96.0;
  Size? _intrinsicSize;

  @override
  void didUpdateWidget(covariant ThreadPollOptionImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.url != widget.image.url ||
        oldWidget.ownerId != widget.ownerId ||
        oldWidget.referer != widget.referer) {
      _intrinsicSize = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    const slot = Size.square(_extent);
    final request = ref
        .watch(forumImageRequestResolverProvider)
        .resolveCacheRequest(
          ForumImageLoadSpec(
            kind: ForumImageKind.threadAttachment,
            url: Uri.parse(widget.image.url),
            ownerId: widget.ownerId,
            referer: widget.referer,
            htmlWidth: widget.image.width,
            htmlHeight: widget.image.height,
            allowReaderOpen: false,
          ),
        );
    // The shared image pipeline probes the encoded file and persists its true
    // dimensions by cache key. Use those for decoding, never to resize the slot.
    final decodeSize = _intrinsicSize == null
        ? slot
        : applyBoxFit(BoxFit.contain, _intrinsicSize!, slot).destination;
    return Semantics(
      image: true,
      label: widget.image.alt,
      child: SizedBox.square(
        dimension: _extent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ColoredBox(
            color: widget.backgroundColor,
            child: CachedLibraryImage(
              request: request,
              remoteDisplayPolicy:
                  CachedImageRemoteDisplayPolicy.afterCacheWrite,
              referer: widget.referer,
              fit: BoxFit.contain,
              width: _extent,
              height: _extent,
              decodeDisplaySize: decodeSize,
              placeholder: const SizedBox.expand(),
              errorPlaceholder: Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: widget.foregroundColor,
                ),
              ),
              onImageResolved: (size) {
                if (size.width > 0 &&
                    size.height > 0 &&
                    size != _intrinsicSize) {
                  setState(() => _intrinsicSize = size);
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
