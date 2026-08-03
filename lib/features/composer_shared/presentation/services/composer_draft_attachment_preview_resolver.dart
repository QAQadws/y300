import 'dart:io';

import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_attachment_verification_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attachment_preview_resolvers.dart';

/// Applies the remote unused-image catalog as a gate in front of local draft
/// previews. New uploads from the current session remain locally renderable;
/// restored aids are local-cache first and remote-thumbnail second.
final class ComposerDraftAttachmentPreviewResolver
    implements ComposerAttachmentPreviewResolver {
  ComposerDraftAttachmentPreviewResolver({
    required List<ComposerImageAttachment> imageAttachments,
    required ComposerDraftAttachmentVerification verification,
    bool Function(String path)? fileExists,
  }) : _attachmentsByAid = <String, ComposerImageAttachment>{
         for (final attachment in imageAttachments)
           if (attachment.aid?.trim() case final aid?)
             if (aid.isNotEmpty) aid: attachment,
       },
       _localResolver = UploadedComposerAttachmentPreviewResolver(
         imageAttachments: imageAttachments,
       ),
       _verification = verification,
       _fileExists = fileExists ?? _defaultFileExists;

  final Map<String, ComposerImageAttachment> _attachmentsByAid;
  final UploadedComposerAttachmentPreviewResolver _localResolver;
  final ComposerDraftAttachmentVerification _verification;
  final bool Function(String path) _fileExists;

  @override
  ComposerAttachmentResolution resolve(String aid) {
    final normalizedAid = aid.trim();
    if (_verification.unverifiedAids.contains(normalizedAid)) {
      return ComposerAttachmentResolution(
        aid: normalizedAid,
        availability: ComposerAttachmentAvailability.missing,
      );
    }

    final remote = _verification.verifiedImagesByAid[normalizedAid];
    final wasChecked = _verification.checkedAids.contains(normalizedAid);
    if (!wasChecked) {
      final local = _localResolver.resolve(normalizedAid);
      if (local.isAvailable ||
          local.availability == ComposerAttachmentAvailability.expired) {
        return local;
      }
      if (remote == null) {
        return local;
      }
    }
    if (remote != null) {
      final attachment = _attachmentsByAid[normalizedAid];
      final cachePath = attachment?.cachePath?.trim();
      if (cachePath != null && cachePath.isNotEmpty && _fileExists(cachePath)) {
        return ComposerAttachmentResolution(
          aid: normalizedAid,
          availability: ComposerAttachmentAvailability.available,
          preview: ComposerLocalImagePreview(cachePath),
          label: attachment?.fileName,
        );
      }
      return ComposerAttachmentResolution(
        aid: normalizedAid,
        availability: ComposerAttachmentAvailability.available,
        preview: ComposerRemoteImagePreview(
          url: remote.thumbnailUri.toString(),
          referer: '${AppConfig.siteBaseUrl}/forum.php',
        ),
        label: remote.fileName.isNotEmpty
            ? remote.fileName
            : remote.description.isNotEmpty
            ? remote.description
            : normalizedAid,
      );
    }

    if (_verification.verified && wasChecked) {
      return ComposerAttachmentResolution(
        aid: normalizedAid,
        availability: ComposerAttachmentAvailability.missing,
      );
    }
    return _localResolver.resolve(normalizedAid);
  }

  static bool _defaultFileExists(String path) => File(path).existsSync();
}
