import 'package:flutter/widgets.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// First-frame evidence for images already mounted in the current viewport.
/// Screen-external images neither block text reading nor trigger extra work.
final class ThreadBodyReadingImageTracker {
  ThreadBodyReadingImageTracker(this.onChanged);
  final VoidCallback onChanged;
  final Map<Object, ({GlobalKey key, bool ready})> _images = {};
  bool _disposed = false;

  bool readyIn(RenderBox viewport) {
    for (final image in _images.values) {
      if (image.ready) continue;
      final box = image.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top < viewport.size.height && top + box.size.height > 0) return false;
    }
    return true;
  }

  void update(Object owner, GlobalKey key, bool ready) {
    if (_disposed) return;
    _images[owner] = (key: key, ready: ready);
    onChanged();
  }

  void remove(Object owner) {
    if (_disposed || _images.remove(owner) == null) return;
    onChanged();
  }

  void dispose() {
    _disposed = true;
    _images.clear();
  }
}

/// Delegates the existing download, display and bounded predecode contracts.
/// Adding reading evidence must not disable the thread image scheduler.
final class ThreadBodyReadingImageHost
    implements ForumHtmlImageHost, ForumHtmlImagePredecodeHost {
  const ThreadBodyReadingImageHost({
    required this.delegate,
    required this.tracker,
  });

  final ForumHtmlImageHost delegate;
  final ThreadBodyReadingImageTracker tracker;

  @override
  ForumHtmlDisplayImage? resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => delegate.resolveImage(
    url: url,
    imageIndex: imageIndex,
    isSticker: isSticker,
    htmlSize: htmlSize,
  );

  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) => delegate.loadDimensions(image);

  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) =>
      delegate.onBlockImageResolved(image, size);

  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) => delegate.prefetchDisk(image, scope: scope);

  @override
  bool canRetainDisplayedImage({
    required ForumHtmlDisplayImage image,
    required Size intrinsicSize,
    required Size displaySize,
    required double devicePixelRatio,
    required int maxDecodedBytes,
  }) =>
      delegate is ForumHtmlImagePredecodeHost &&
      (delegate as ForumHtmlImagePredecodeHost).canRetainDisplayedImage(
        image: image,
        intrinsicSize: intrinsicSize,
        displaySize: displaySize,
        devicePixelRatio: devicePixelRatio,
        maxDecodedBytes: maxDecodedBytes,
      );

  @override
  Future<ForumHtmlImagePreparationOutcome> predecodeImage({
    required ForumHtmlDisplayImage image,
    required BuildContext context,
    required Size displaySize,
    required ForumHtmlImageWorkScope scope,
    required int maxDecodedBytes,
  }) async {
    if (delegate is ForumHtmlImagePredecodeHost) {
      return (delegate as ForumHtmlImagePredecodeHost).predecodeImage(
        image: image,
        context: context,
        displaySize: displaySize,
        scope: scope,
        maxDecodedBytes: maxDecodedBytes,
      );
    }
    await delegate.prefetchDisk(image, scope: scope);
    return !scope.isActive
        ? ForumHtmlImagePreparationOutcome.cancelled
        : ForumHtmlImagePreparationOutcome.diskOnly;
  }

  @override
  Widget buildImage({
    required ForumHtmlDisplayImage image,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    VoidCallback? onRetry,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) {
    Widget build(VoidCallback ready) => delegate.buildImage(
      image: image,
      fit: fit,
      placeholder: placeholder,
      width: width,
      height: height,
      errorPlaceholder: errorPlaceholder,
      onRetry: onRetry,
      onImageResolved: onImageResolved,
      onImageFailed: onImageFailed,
      onFirstFrameRendered: () {
        ready();
        onFirstFrameRendered?.call();
      },
      showDelayedLoadingIndicator: showDelayedLoadingIndicator,
      waitForCacheWrite: waitForCacheWrite,
      retryToken: retryToken,
    );
    return image.isSticker
        ? build(() {})
        : _ReadingImage(
            identity: (image.identity, retryToken),
            tracker: tracker,
            builder: build,
          );
  }
}

class _ReadingImage extends StatefulWidget {
  const _ReadingImage({
    required this.identity,
    required this.tracker,
    required this.builder,
  });
  final Object identity;
  final ThreadBodyReadingImageTracker tracker;
  final Widget Function(VoidCallback ready) builder;

  @override
  State<_ReadingImage> createState() => _ReadingImageState();
}

class _ReadingImageState extends State<_ReadingImage> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.tracker.update(this, _key, false);
  }

  @override
  void didUpdateWidget(covariant _ReadingImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tracker, widget.tracker)) {
      oldWidget.tracker.remove(this);
    }
    if (!identical(oldWidget.tracker, widget.tracker) ||
        oldWidget.identity != widget.identity) {
      widget.tracker.update(this, _key, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = widget.identity;
    final tracker = widget.tracker;
    return KeyedSubtree(
      key: _key,
      child: widget.builder(() {
        if (mounted &&
            identity == widget.identity &&
            identical(tracker, widget.tracker)) {
          tracker.update(this, _key, true);
        }
      }),
    );
  }

  @override
  void dispose() {
    widget.tracker.remove(this);
    super.dispose();
  }
}
