import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/image_loading/domain/app_image_source.dart';
import 'package:y300/features/image_loading/presentation/app_image.dart';
import 'package:y300/shared/widgets/forum_media_loading_style.dart';

typedef ComposerLocalImageBuilder = Widget Function(File file, Key key);
typedef ComposerLocalFileExists = bool Function(File file);

Widget defaultComposerLocalImageBuilder(File file, Key key) {
  return Image.file(
    file,
    key: key,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}

bool defaultComposerLocalFileExists(File file) {
  return file.existsSync();
}

/// Renders one already-resolved image source. Resolution remains in domain;
/// this adapter owns Flutter image loading and the shared request-header path.
class ComposerAttachmentPreviewImage extends ConsumerWidget {
  const ComposerAttachmentPreviewImage({
    super.key,
    required this.resolution,
    required this.maxWidth,
    this.imageKey,
    this.localImageBuilder = defaultComposerLocalImageBuilder,
    this.localFileExists = defaultComposerLocalFileExists,
  }) : _thumbnailHeight = null;

  const ComposerAttachmentPreviewImage.thumbnail({
    super.key,
    required this.resolution,
    required double width,
    required double height,
    this.imageKey,
  }) : maxWidth = width,
       _thumbnailHeight = height,
       localImageBuilder = defaultComposerLocalImageBuilder,
       localFileExists = defaultComposerLocalFileExists;

  final ComposerAttachmentResolution resolution;
  final double maxWidth;
  final Key? imageKey;
  final ComposerLocalImageBuilder localImageBuilder;
  final ComposerLocalFileExists localFileExists;
  final double? _thumbnailHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = resolution.isAvailable ? resolution.preview : null;
    if (_thumbnailHeight case final height?) {
      return _buildThumbnail(source, height);
    }
    if (source == null) {
      return const SizedBox.shrink();
    }
    return switch (source) {
      ComposerLocalImagePreview(:final path) => _buildLocal(path),
      ComposerRemoteImagePreview(:final url, :final referer) => _buildRemote(
        url,
        referer,
      ),
    };
  }

  Widget _buildThumbnail(ComposerImagePreviewSource? source, double height) {
    const failed = Center(child: Icon(Icons.broken_image_outlined));
    final (localPath, networkSource) = switch (source) {
      ComposerLocalImagePreview(:final path) => (path, null),
      ComposerRemoteImagePreview(:final url, :final referer) => (
        null,
        NetworkAppImageSource(url: url, referer: referer),
      ),
      null => (null, null),
    };

    return SizedBox(
      width: maxWidth,
      height: height,
      child:
          source == null ||
              (localPath != null && !localFileExists(File(localPath)))
          ? failed
          : AppImage(
              key:
                  imageKey ??
                  ValueKey<String>('composer-thumbnail-${resolution.aid}'),
              localPath: localPath,
              networkSource: networkSource,
              fit: BoxFit.contain,
              fadeInDuration: ForumMediaLoadingStyle.fadeInDuration,
              placeholder: const Center(child: Icon(Icons.image_outlined)),
              errorPlaceholder: failed,
            ),
    );
  }

  Widget _buildLocal(String path) {
    final file = File(path);
    if (!localFileExists(file)) {
      return const SizedBox.shrink();
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: localImageBuilder(
        file,
        imageKey ?? ValueKey<String>('composer-local-${resolution.aid}'),
      ),
    );
  }

  Widget _buildRemote(String url, String referer) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: AppImage(
        key: imageKey ?? ValueKey<String>('composer-remote-${resolution.aid}'),
        networkSource: NetworkAppImageSource(url: url, referer: referer),
        fit: BoxFit.contain,
        placeholder: const SizedBox(
          width: 32,
          height: 32,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorPlaceholder: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}
