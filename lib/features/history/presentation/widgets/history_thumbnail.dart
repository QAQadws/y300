import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/history/domain/models/history_models.dart';

typedef HistoryLocalFileExists = bool Function(String path);

class HistoryResolvedThumbnail {
  const HistoryResolvedThumbnail({
    this.localPath,
    this.remoteUrl,
    this.alignment = Alignment.center,
  });

  final String? localPath;
  final String? remoteUrl;
  final Alignment alignment;

  bool get hasImage => localPath != null || remoteUrl != null;
}

class HistoryThumbnailResolver {
  const HistoryThumbnailResolver();

  HistoryResolvedThumbnail resolve(
    HistoryThumbnailSnapshot? snapshot, {
    HistoryLocalFileExists fileExists = _defaultFileExists,
  }) {
    if (snapshot == null) {
      return const HistoryResolvedThumbnail();
    }
    final localCandidate = snapshot.localPath?.trim();
    final localPath =
        localCandidate != null &&
            localCandidate.isNotEmpty &&
            fileExists(localCandidate)
        ? localCandidate
        : null;
    final remoteUrl = _validRemoteUrl(snapshot.remoteUrl);
    return HistoryResolvedThumbnail(
      localPath: localPath,
      remoteUrl: remoteUrl,
      alignment: Alignment(
        _alignmentAxis(snapshot.focusX),
        _alignmentAxis(snapshot.focusY),
      ),
    );
  }

  static bool _defaultFileExists(String path) => io.File(path).existsSync();

  String? _validRemoteUrl(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }

  double _alignmentAxis(double? focus) {
    if (focus == null || !focus.isFinite) {
      return 0;
    }
    return focus.clamp(0.0, 1.0) * 2 - 1;
  }
}

class HistoryThumbnail extends StatelessWidget {
  const HistoryThumbnail({
    super.key,
    required this.entry,
    this.headerBuilder,
    this.resolver = const HistoryThumbnailResolver(),
  });

  static const double width = 64;
  static const double height = 88;

  final HistoryEntry entry;
  final ImageRequestHeaderBuilder? headerBuilder;
  final HistoryThumbnailResolver resolver;

  @override
  Widget build(BuildContext context) {
    final resolved = resolver.resolve(entry.thumbnail);
    final fallback = _HistoryThumbnailFallback(type: entry.target.type);
    return ClipRRect(
      key: ValueKey<String>('history-thumbnail-${entry.target}'),
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: height,
        child: resolved.hasImage
            ? LibraryCachedImage(
                localPath: resolved.localPath,
                imageUrl: resolved.remoteUrl,
                fit: BoxFit.cover,
                width: width,
                height: height,
                decodeDisplaySize: const Size(width, height),
                alignment: resolved.alignment,
                headerBuilder: headerBuilder,
                placeholder: fallback,
                errorPlaceholder: fallback,
              )
            : fallback,
      ),
    );
  }
}

class _HistoryThumbnailFallback extends StatelessWidget {
  const _HistoryThumbnailFallback({required this.type});

  final HistoryTargetType type;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = switch (type) {
      HistoryTargetType.thread => Icons.forum_outlined,
      HistoryTargetType.comic => Icons.collections_bookmark_outlined,
      HistoryTargetType.novel => Icons.local_library_outlined,
    };
    return ColoredBox(
      key: ValueKey<String>('history-thumbnail-fallback-${type.name}'),
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          icon,
          size: 28,
          color: colors.onSurfaceVariant.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}
