import 'package:flutter/widgets.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// Tracks only already mounted image widgets; it never requests hidden images.
final class NovelReadingImageTracker {
  NovelReadingImageTracker(this.onChanged);
  final void Function(bool ready) onChanged;
  final Map<Object, bool> _members = {};
  bool _disposed = false;
  bool _scheduled = false;
  bool get isReady => _members.values.every((value) => value);
  void update(Object member, bool ready) {
    if (_disposed || _members[member] == ready) return;
    _members[member] = ready;
    _notify();
  }

  void remove(Object member) {
    if (_disposed || _members.remove(member) == null) return;
    _notify();
  }

  void _notify() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) onChanged(isReady);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    _disposed = true;
    _members.clear();
  }
}

final class NovelReadingImageHost implements ForumHtmlImageHost {
  const NovelReadingImageHost({required this.delegate, required this.tracker});
  final ForumHtmlImageHost delegate;
  final NovelReadingImageTracker tracker;
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
  final NovelReadingImageTracker tracker;
  final Widget Function(VoidCallback ready) builder;
  @override
  State<_ReadingImage> createState() => _ReadingImageState();
}

class _ReadingImageState extends State<_ReadingImage> {
  @override
  void initState() {
    super.initState();
    widget.tracker.update(this, false);
  }

  @override
  void didUpdateWidget(covariant _ReadingImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracker != widget.tracker) {
      oldWidget.tracker.remove(this);
    }
    if (oldWidget.tracker != widget.tracker ||
        oldWidget.identity != widget.identity) {
      widget.tracker.update(this, false);
    }
  }

  @override
  void dispose() {
    widget.tracker.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identity = widget.identity;
    final tracker = widget.tracker;
    return widget.builder(() {
      if (mounted &&
          identity == widget.identity &&
          identical(tracker, widget.tracker)) {
        tracker.update(this, true);
      }
    });
  }
}
