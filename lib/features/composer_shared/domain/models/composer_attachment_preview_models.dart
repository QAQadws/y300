/// Availability of an attachment referenced by the editor message.
enum ComposerAttachmentAvailability {
  available,
  deleting,
  deleted,
  expired,
  missing,
}

/// A source that can be rendered by the shared composer presentation layer.
sealed class ComposerImagePreviewSource {
  const ComposerImagePreviewSource();
}

final class ComposerLocalImagePreview extends ComposerImagePreviewSource {
  const ComposerLocalImagePreview(this.path);

  final String path;
}

final class ComposerRemoteImagePreview extends ComposerImagePreviewSource {
  const ComposerRemoteImagePreview({required this.url, required this.referer});

  final String url;
  final String referer;
}

/// The result of resolving one BBCode attachment aid for the current editor
/// session.
final class ComposerAttachmentResolution {
  const ComposerAttachmentResolution({
    required this.aid,
    required this.availability,
    this.preview,
    this.label,
  });

  final String aid;
  final ComposerAttachmentAvailability availability;
  final ComposerImagePreviewSource? preview;
  final String? label;

  bool get isAvailable =>
      availability == ComposerAttachmentAvailability.available &&
      preview != null;
}

abstract interface class ComposerAttachmentPreviewResolver {
  ComposerAttachmentResolution resolve(String aid);
}
