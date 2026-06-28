import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/widgets.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

typedef ContinuousImageLocalPathResolver =
    FutureOr<String?> Function(ContinuousImageItem item);

/// Presentation-layer decoded-image preheater for reader pages.
///
/// Disk/cache preloading only makes the bytes available. This helper warms
/// Flutter's decoded image cache for the current page window so horizontal page
/// turns are less likely to show a blank/loading frame.
class ContinuousImageDecodePreheater {
  const ContinuousImageDecodePreheater({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  void precacheWindow({
    required BuildContext context,
    required List<ContinuousImageItem> items,
    required int centerIndex,
    required Set<String> warmedKeys,
    ImageRequestHeaderBuilder? imageHeaderBuilder,
    ContinuousImageLocalPathResolver? localPathResolver,
    int radius = 1,
    bool Function()? isMounted,
  }) {
    if (items.isEmpty || radius < 0) {
      return;
    }
    final start = (centerIndex - radius).clamp(0, items.length - 1).toInt();
    final end = (centerIndex + radius).clamp(0, items.length - 1).toInt();
    for (var index = start; index <= end; index++) {
      final item = items[index];
      final key = '${item.ownerId}:${item.index}:${item.cacheKey}:${item.url}';
      if (!warmedKeys.add(key)) {
        continue;
      }
      unawaited(
        _precacheItem(
          context: context,
          item: item,
          imageHeaderBuilder: imageHeaderBuilder,
          localPathResolver: localPathResolver,
          isMounted: isMounted,
        ).catchError((_) {
          warmedKeys.remove(key);
        }),
      );
    }
  }

  Future<void> _precacheItem({
    required BuildContext context,
    required ContinuousImageItem item,
    required ImageRequestHeaderBuilder? imageHeaderBuilder,
    required ContinuousImageLocalPathResolver? localPathResolver,
    required bool Function()? isMounted,
  }) async {
    final localPath = (await localPathResolver?.call(item))?.trim();
    if (!context.mounted || isMounted?.call() == false) {
      return;
    }
    if (localPath != null && localPath.isNotEmpty) {
      final file = io.File(localPath);
      if (file.existsSync()) {
        await precacheImage(FileImage(file), context, onError: (_, _) {});
        return;
      }
    }

    final remote = _normalizeRemoteUrl(item.url);
    if (remote == null || remote.isEmpty) {
      return;
    }
    final headers = await imageHeaderBuilder?.buildHeaders(remote);
    if (!context.mounted || isMounted?.call() == false) {
      return;
    }
    await precacheImage(
      NetworkImage(
        remote,
        headers: headers == null || headers.isEmpty ? null : headers,
      ),
      context,
      onError: (_, _) {},
    );
  }

  String? _normalizeRemoteUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return _urlResolver.resolve(trimmed) ?? trimmed;
  }
}
