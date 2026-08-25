import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_unused_image_management_controller.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_image_delete_button.dart';
import 'package:y300/l10n/app_localizations.dart';

class ComposerUnusedImageManagementPage extends ConsumerWidget {
  const ComposerUnusedImageManagementPage({super.key});

  static const routeName = 'composer-unused-images';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(
      composerUnusedImageManagementControllerProvider,
    );
    return Scaffold(
      key: const Key('composer-unused-image-management-page'),
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).unusedImagesPageTitle),
      ),
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _UnusedImagesLoadError(
          onRetry: () => ref
              .read(composerUnusedImageManagementControllerProvider.notifier)
              .refreshCatalog(),
        ),
        data: (state) => _UnusedImagesCatalog(state: state),
      ),
    );
  }
}

class _UnusedImagesLoadError extends StatelessWidget {
  const _UnusedImagesLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: onRetry,
      child: CustomScrollView(
        key: const Key('unused-images-error-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 44),
                    const SizedBox(height: 12),
                    Text(
                      l10n.unusedImagesLoadFailed,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      key: const Key('unused-images-retry'),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.commonRetry),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnusedImagesCatalog extends ConsumerWidget {
  const _UnusedImagesCatalog({required this.state});

  final ComposerUnusedImageManagementState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(
      composerUnusedImageManagementControllerProvider.notifier,
    );
    if (state.images.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.refreshCatalog,
        child: CustomScrollView(
          key: const Key('unused-images-empty-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    AppLocalizations.of(context).unusedImagesEmpty,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.refreshCatalog,
      child: GridView.builder(
        key: const Key('unused-images-grid'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: state.images.length,
        itemBuilder: (context, index) {
          final image = state.images[index];
          return _UnusedImageCard(
            image: image,
            thumbnailPath: state.thumbnailPaths[image.aid],
            isLoading: state.loadingThumbnailAids.contains(image.aid),
            didFail: state.failedThumbnailAids.contains(image.aid),
            isDeleting: state.deletingAids.contains(image.aid),
            onThumbnailDecodeFailed: controller.reportThumbnailDecodeFailure,
          );
        },
      ),
    );
  }
}

class _UnusedImageCard extends ConsumerWidget {
  const _UnusedImageCard({
    required this.image,
    required this.thumbnailPath,
    required this.isLoading,
    required this.didFail,
    required this.isDeleting,
    required this.onThumbnailDecodeFailed,
  });

  final ComposerUnusedImage image;
  final String? thumbnailPath;
  final bool isLoading;
  final bool didFail;
  final bool isDeleting;
  final void Function({required String aid, required String localPath})
  onThumbnailDecodeFailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final label = image.fileName.trim().isNotEmpty
        ? image.fileName.trim()
        : image.description.trim().isNotEmpty
        ? image.description.trim()
        : image.aid;
    return Card(
      key: Key('unused-image-card-${image.aid}'),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(child: _buildThumbnail()),
                      PositionedDirectional(
                        top: 0,
                        end: 0,
                        child: ComposerImageDeleteButton(
                          key: Key('unused-image-delete-${image.aid}'),
                          visualKey: Key(
                            'unused-image-delete-visual-${image.aid}',
                          ),
                          tooltip: l10n.unusedImagesDeleteTooltip,
                          isBusy: isDeleting,
                          onPressed: isDeleting
                              ? null
                              : () => _confirmDelete(context, ref),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    final path = thumbnailPath?.trim();
    if (path != null && path.isNotEmpty) {
      return Image.file(
        File(path),
        key: Key('unused-image-thumbnail-${image.aid}'),
        fit: BoxFit.contain,
        errorBuilder: (imageContext, _, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!imageContext.mounted) {
              return;
            }
            onThumbnailDecodeFailed(aid: image.aid, localPath: path);
          });
          return const Icon(Icons.broken_image_outlined);
        },
      );
    }
    if (isLoading) {
      return const SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      didFail ? Icons.broken_image_outlined : Icons.image_outlined,
      size: 40,
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.unusedImagesDeleteTitle),
        content: Text(l10n.unusedImagesDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('unused-images-confirm-delete'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final deleted = await ref
        .read(composerUnusedImageManagementControllerProvider.notifier)
        .deleteImage(image.aid);
    if (!deleted && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.unusedImagesDeleteFailed)));
    }
  }
}
