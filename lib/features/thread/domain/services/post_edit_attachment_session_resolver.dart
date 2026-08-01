import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attachment_preview_resolvers.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

/// Resolves attachment references for one native post-edit session.
///
/// Remote images remain feature-owned session data. They never become
/// [ComposerImageAttachment] instances, so they cannot enter upload drafts or
/// the local upload maintenance job.
final class PostEditAttachmentSessionResolver
    implements ComposerAttachmentPreviewResolver {
  PostEditAttachmentSessionResolver({
    required this.session,
    required List<ComposerImageAttachment> localAttachments,
    required this.referer,
  }) : _localAttachmentsByAid = {
         for (final attachment in localAttachments)
           if (attachment.hasAid) attachment.aid!.trim(): attachment,
       },
       _localResolver = UploadedComposerAttachmentPreviewResolver(
         imageAttachments: localAttachments,
       );

  final PostEditAttachmentSession session;
  final String referer;
  final Map<String, ComposerImageAttachment> _localAttachmentsByAid;
  final UploadedComposerAttachmentPreviewResolver _localResolver;

  @override
  ComposerAttachmentResolution resolve(String aid) {
    final normalizedAid = aid.trim();
    if (normalizedAid.isEmpty) {
      return const ComposerAttachmentResolution(
        aid: '',
        availability: ComposerAttachmentAvailability.missing,
      );
    }

    final existing = session.existingImagesByAid[normalizedAid];
    final label = existing?.fileName ?? normalizedAid;
    if (session.deletedAidTombstones.contains(normalizedAid)) {
      return ComposerAttachmentResolution(
        aid: normalizedAid,
        availability: ComposerAttachmentAvailability.deleted,
        label: label,
      );
    }
    if (session.deletingAids.contains(normalizedAid)) {
      return ComposerAttachmentResolution(
        aid: normalizedAid,
        availability: ComposerAttachmentAvailability.deleting,
        label: label,
      );
    }

    if (_localAttachmentsByAid.containsKey(normalizedAid)) {
      return _localResolver.resolve(normalizedAid);
    }

    if (existing == null) {
      return ComposerAttachmentResolution(
        aid: normalizedAid,
        availability: ComposerAttachmentAvailability.missing,
      );
    }
    final uri = existing.imageUri;
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return ComposerAttachmentResolution(
        aid: normalizedAid,
        availability: ComposerAttachmentAvailability.missing,
        label: label,
      );
    }
    return ComposerAttachmentResolution(
      aid: normalizedAid,
      availability: ComposerAttachmentAvailability.available,
      preview: ComposerRemoteImagePreview(
        url: uri.toString(),
        referer: referer,
      ),
      label: label,
    );
  }
}
