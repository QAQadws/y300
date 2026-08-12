import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_providers.dart';
import 'package:y300/features/library_shared/data/services/library_cover_decode_scheduler.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_decode_policy.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_image_provider.dart';

abstract final class LibraryCoverProviderResolver {
  static LibraryCoverImageProvider resolve({
    required LibraryCoverAssetRef asset,
    required Size displaySize,
    required double devicePixelRatio,
    required LibraryCoverStore store,
    required LibraryCoverDecodeScheduler scheduler,
  }) {
    return LibraryCoverImageProvider(
      asset: asset,
      decodeTarget: LibraryCoverDecodeTarget.fromDisplaySize(
        displaySize: displaySize,
        devicePixelRatio: devicePixelRatio,
      ),
      store: store,
      scheduler: scheduler,
    );
  }
}

class LibraryCoverImage extends ConsumerWidget {
  const LibraryCoverImage({
    super.key,
    required this.asset,
    required this.fit,
    required this.placeholder,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
  });

  final LibraryCoverAssetRef asset;
  final BoxFit fit;
  final Widget placeholder;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          _finite(width, constraints.maxWidth),
          _finite(height, constraints.maxHeight),
        );
        final provider = LibraryCoverProviderResolver.resolve(
          asset: asset,
          displaySize: size,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          store: ref.watch(libraryCoverStoreProvider),
          scheduler: ref.watch(libraryCoverDecodeSchedulerProvider),
        );
        final image = LibraryCoverProviderImage(
          provider: provider,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          placeholder: placeholder,
        );
        return image;
      },
    );
  }

  double _finite(double? preferred, double fallback) {
    if (preferred != null && preferred.isFinite && preferred > 0) {
      return preferred;
    }
    return fallback.isFinite && fallback > 0 ? fallback : double.nan;
  }
}

class LibraryCoverProviderImage extends StatelessWidget {
  const LibraryCoverProviderImage({
    super.key,
    required this.provider,
    required this.fit,
    required this.placeholder,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
  });

  final LibraryCoverImageProvider provider;
  final BoxFit fit;
  final Widget placeholder;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null || wasSynchronouslyLoaded) {
          return child;
        }
        return placeholder;
      },
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}
