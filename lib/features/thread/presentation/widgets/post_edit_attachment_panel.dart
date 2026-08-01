import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_attachment_preview.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';
import 'package:y300/l10n/app_localizations.dart';

class PostEditAttachmentPanel extends StatelessWidget {
  const PostEditAttachmentPanel({
    super.key,
    required this.state,
    required this.resolver,
    required this.onDeleteImage,
  });

  final PostEditComposerState state;
  final ComposerAttachmentPreviewResolver resolver;
  final ValueChanged<String> onDeleteImage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cards = _cards();
    return Container(
      key: const Key('post-edit-attachment-panel-content'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: cards.isEmpty
          ? Text(l10n.postEditNoImages)
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final card in cards)
                  _PostEditAttachmentCard(
                    card: card,
                    resolver: resolver,
                    onDelete: onDeleteImage,
                  ),
              ],
            ),
    );
  }

  List<_PostEditAttachmentCardData> _cards() {
    final tombstones = state.attachmentSession.deletedAidTombstones;
    final cards = <_PostEditAttachmentCardData>[
      for (final image in state.attachmentSession.existingImagesByAid.values)
        if (!tombstones.contains(image.aid))
          _PostEditAttachmentCardData.remote(image),
      for (final attachment in [
        ...state.imageAttachments,
      ]..sort((a, b) => a.order.compareTo(b.order)))
        if (attachment.aid == null ||
            !tombstones.contains(attachment.aid!.trim()))
          _PostEditAttachmentCardData.local(attachment),
    ];
    return cards;
  }
}

final class _PostEditAttachmentCardData {
  const _PostEditAttachmentCardData.remote(this.remoteImage)
    : localAttachment = null;

  const _PostEditAttachmentCardData.local(this.localAttachment)
    : remoteImage = null;

  final PostEditExistingImage? remoteImage;
  final ComposerImageAttachment? localAttachment;

  String get aid => remoteImage?.aid ?? localAttachment?.aid?.trim() ?? '';

  String get label => remoteImage?.fileName ?? localAttachment?.fileName ?? aid;
}

class _PostEditAttachmentCard extends StatelessWidget {
  const _PostEditAttachmentCard({
    required this.card,
    required this.resolver,
    required this.onDelete,
  });

  final _PostEditAttachmentCardData card;
  final ComposerAttachmentPreviewResolver resolver;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final aid = card.aid;
    final resolution = _resolve();
    final canDelete =
        aid.isNotEmpty &&
        resolution.availability != ComposerAttachmentAvailability.deleting;
    return SizedBox(
      width: 116,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 104,
            height: 88,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: resolution.isAvailable
                        ? Padding(
                            padding: const EdgeInsets.all(4),
                            child: ComposerAttachmentPreviewImage(
                              resolution: resolution,
                              maxWidth: 96,
                              imageKey: Key('post-edit-image-$aid'),
                            ),
                          )
                        : Semantics(
                            label:
                                resolution.availability ==
                                    ComposerAttachmentAvailability.deleting
                                ? l10n.postEditAttachmentDeleting
                                : null,
                            child: Icon(
                              resolution.availability ==
                                      ComposerAttachmentAvailability.deleting
                                  ? Icons.hourglass_top
                                  : Icons.broken_image_outlined,
                            ),
                          ),
                  ),
                ),
                if (canDelete)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Semantics(
                      button: true,
                      label: l10n.postEditDeleteImage,
                      child: IconButton(
                        key: Key('post-edit-delete-image-$aid'),
                        tooltip: l10n.postEditDeleteImage,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                        ),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _confirmDelete(context, aid),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            card.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  ComposerAttachmentResolution _resolve() {
    final local = card.localAttachment;
    if (local != null && !local.hasAid) {
      if (local.status == ComposerImageAttachmentStatus.expired) {
        return ComposerAttachmentResolution(
          aid: '',
          availability: ComposerAttachmentAvailability.expired,
          label: local.fileName,
        );
      }
      return ComposerAttachmentResolution(
        aid: '',
        availability: ComposerAttachmentAvailability.available,
        preview: ComposerLocalImagePreview(local.previewPath),
        label: local.fileName,
      );
    }
    return resolver.resolve(card.aid);
  }

  Future<void> _confirmDelete(BuildContext context, String aid) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.postEditDeleteImageTitle),
        content: Text(l10n.postEditDeleteImageBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('post-edit-confirm-delete-image'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.postEditDeleteImageConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onDelete(aid);
    }
  }
}
