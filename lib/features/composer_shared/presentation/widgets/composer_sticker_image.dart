import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';

/// Composer-only sticker image.
///
/// This widget never renders the remote URL directly.  It displays an existing
/// cached file immediately, then asks the composer sticker loader to fill cache
/// misses through its serial, rate-limited queue.
class ComposerStickerImage extends ConsumerStatefulWidget {
  const ComposerStickerImage({
    super.key,
    required this.sticker,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    required this.placeholder,
    this.errorPlaceholder,
  });

  final StickerItem sticker;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget placeholder;
  final Widget? errorPlaceholder;

  @override
  ConsumerState<ComposerStickerImage> createState() {
    return _ComposerStickerImageState();
  }
}

class _ComposerStickerImageState extends ConsumerState<ComposerStickerImage> {
  String? _localPath;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ComposerStickerImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sticker.cacheKey != widget.sticker.cacheKey ||
        oldWidget.sticker.imageUrl != widget.sticker.imageUrl) {
      _localPath = null;
      _failed = false;
      _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localPath = _localPath?.trim();
    if (localPath != null && localPath.isNotEmpty) {
      final file = io.File(localPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallback,
        );
      }
    }
    return _failed ? _fallback : widget.placeholder;
  }

  void _resolve() {
    final request = ForumImageCacheRequests.remoteSmiley(
      url: widget.sticker.imageUrl,
    );
    final generation = ++_generation;
    unawaited(
      ref
          .read(composerStickerImageCacheLoaderProvider)
          .ensureCached(request)
          .then((result) {
            if (!mounted || generation != _generation) {
              return;
            }
            final localPath = result.localPath?.trim();
            if (result.success && localPath != null && localPath.isNotEmpty) {
              setState(() {
                _localPath = localPath;
                _failed = false;
              });
              return;
            }
            setState(() {
              _failed = true;
            });
          })
          .catchError((_) {
            if (!mounted || generation != _generation) {
              return;
            }
            setState(() {
              _failed = true;
            });
          }),
    );
  }

  Widget get _fallback => widget.errorPlaceholder ?? widget.placeholder;
}
