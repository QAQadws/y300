import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';

/// Resolves the local images owned by reply/posting upload sessions.
///
/// Remote edit-page images deliberately use a different resolver. Keeping
/// this adapter local-only prevents server attachments from entering the
/// upload draft model and its expiry maintenance lifecycle.
final class UploadedComposerAttachmentPreviewResolver
    implements ComposerAttachmentPreviewResolver {
  UploadedComposerAttachmentPreviewResolver({
    required List<ComposerImageAttachment> imageAttachments,
  }) : _attachmentsByAid = {
         for (final attachment in imageAttachments)
           if (attachment.hasAid) attachment.aid!.trim(): attachment,
       };

  final Map<String, ComposerImageAttachment> _attachmentsByAid;

  @override
  ComposerAttachmentResolution resolve(String aid) {
    final normalizedAid = aid.trim();
    final attachment = _attachmentsByAid[normalizedAid];
    if (attachment == null || !attachment.hasAid) {
      return ComposerAttachmentResolution(
        aid: normalizedAid,
        availability: ComposerAttachmentAvailability.missing,
      );
    }
    if (attachment.status == ComposerImageAttachmentStatus.expired) {
      return ComposerAttachmentResolution(
        aid: normalizedAid,
        availability: ComposerAttachmentAvailability.expired,
        label: attachment.fileName,
      );
    }
    if (!attachment.canEnterSubmitPayload) {
      return ComposerAttachmentResolution(
        aid: normalizedAid,
        availability: ComposerAttachmentAvailability.missing,
        label: attachment.fileName,
      );
    }
    return ComposerAttachmentResolution(
      aid: normalizedAid,
      availability: ComposerAttachmentAvailability.available,
      preview: ComposerLocalImagePreview(attachment.previewPath),
      label: attachment.fileName,
    );
  }
}

/// A small immutable registry adapter for feature-owned remote attachments.
///
/// The feature that owns the registry (for example, post edit) creates the
/// resolutions and passes this adapter into the shared composer. The shared
/// layer therefore knows how to render a remote source without depending on
/// the feature's protocol models.
final class MapComposerAttachmentPreviewResolver
    implements ComposerAttachmentPreviewResolver {
  MapComposerAttachmentPreviewResolver({
    required Map<String, ComposerAttachmentResolution> resolutions,
  }) : _resolutions = Map.unmodifiable(resolutions);

  final Map<String, ComposerAttachmentResolution> _resolutions;

  @override
  ComposerAttachmentResolution resolve(String aid) {
    final normalizedAid = aid.trim();
    return _resolutions[normalizedAid] ??
        ComposerAttachmentResolution(
          aid: normalizedAid,
          availability: ComposerAttachmentAvailability.missing,
        );
  }
}

/// Resolves a local upload first and then falls back to a feature-owned
/// registry of remote images.
final class CompositeComposerAttachmentPreviewResolver
    implements ComposerAttachmentPreviewResolver {
  const CompositeComposerAttachmentPreviewResolver({
    required this.local,
    required this.remote,
  });

  final ComposerAttachmentPreviewResolver local;
  final ComposerAttachmentPreviewResolver remote;

  @override
  ComposerAttachmentResolution resolve(String aid) {
    final localResolution = local.resolve(aid);
    if (localResolution.isAvailable ||
        localResolution.availability !=
            ComposerAttachmentAvailability.missing) {
      return localResolution;
    }
    return remote.resolve(aid);
  }
}
