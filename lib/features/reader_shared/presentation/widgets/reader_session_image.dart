import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_store.dart';

/// Shared reader image that consumes session preparation before persistent
/// cache lookup and remote fallback.
///
/// Only this image subtree listens to local-path promotion. The reader engine,
/// list/page container, and zoom surface keep their identities unchanged.
class ReaderSessionImage extends StatelessWidget {
  const ReaderSessionImage({
    super.key,
    required this.sessionBinding,
    required this.cacheRequest,
    required this.fit,
    required this.expectedDisplaySize,
    required this.placeholder,
    this.width,
    this.height,
    this.errorPlaceholder,
    this.headerBuilder,
    this.loadingIndicatorColor,
    this.onImageResolved,
    this.onImageFailed,
    this.imageProviderOverride,
    this.remoteImageProviderOverride,
    this.retryToken = 0,
  });

  final ReaderImageSessionBinding sessionBinding;
  final ImageCacheRequest cacheRequest;
  final BoxFit fit;
  final Size expectedDisplaySize;
  final double? width;
  final double? height;
  final Widget placeholder;
  final Widget? errorPlaceholder;
  final ImageRequestHeaderBuilder? headerBuilder;
  final Color? loadingIndicatorColor;
  final ValueChanged<Size>? onImageResolved;
  final VoidCallback? onImageFailed;
  @visibleForTesting
  final ImageProvider? imageProviderOverride;
  @visibleForTesting
  final ImageProvider? remoteImageProviderOverride;
  final int retryToken;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderImageSessionEntry>(
      valueListenable: sessionBinding,
      builder: (context, entry, child) => CachedLibraryImage(
        key: ValueKey<String>('reader-session-image-${entry.itemId}'),
        request: cacheRequest,
        preferredLocalPath: entry.localPath,
        decodeDisplaySize: expectedDisplaySize,
        fit: fit,
        width: width,
        height: height,
        placeholder: placeholder,
        errorPlaceholder: errorPlaceholder,
        headerBuilder: headerBuilder,
        onImageResolved: onImageResolved,
        onImageFailed: onImageFailed,
        onLocalPathResolved: sessionBinding.promoteLocalPath,
        imageProviderOverride: imageProviderOverride,
        remoteImageProviderOverride: remoteImageProviderOverride,
        retryToken: retryToken,
        showDelayedLoadingIndicator: true,
        loadingIndicatorColor: loadingIndicatorColor,
      ),
    );
  }
}
