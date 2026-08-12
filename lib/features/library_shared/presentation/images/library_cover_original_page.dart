import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_decode_policy.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_image_provider.dart';
import 'package:y300/shared/widgets/library_cover_placeholder.dart';

/// Full-resolution viewer whose bitmap is evicted when the route closes so it
/// cannot displace shelf thumbnails from the shared Flutter image cache.
class LibraryCoverOriginalPage extends ConsumerStatefulWidget {
  const LibraryCoverOriginalPage({super.key, required this.asset});

  final LibraryCoverAssetRef asset;

  @override
  ConsumerState<LibraryCoverOriginalPage> createState() =>
      _LibraryCoverOriginalPageState();
}

class _LibraryCoverOriginalPageState
    extends ConsumerState<LibraryCoverOriginalPage> {
  late final LibraryCoverImageProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = LibraryCoverImageProvider(
      asset: widget.asset,
      decodeTarget: const LibraryCoverDecodeTarget.original(),
      store: ref.read(libraryCoverStoreProvider),
      scheduler: ref.read(libraryCoverDecodeSchedulerProvider),
    );
  }

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.evict(
      _provider.cacheKey,
      includeLive: true,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 6,
          child: Image(
            image: _provider,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) =>
                const LibraryCoverPlaceholder(
                  key: Key('library-cover-original-placeholder'),
                  color: Colors.black,
                ),
          ),
        ),
      ),
    );
  }
}
