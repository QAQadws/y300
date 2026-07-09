import 'dart:convert';

import 'package:y300/core/config/app_config.dart';

/// Stable logical image cache keys shared by comics, novels and future modules.
///
/// These keys intentionally do not contain transient remote URLs.  The remote
/// URL is only the last known source used to populate the local file.
abstract final class ImageCacheKeys {
  static String comicCover(String comicId) {
    return 'cover/comic/${_normalizePart(comicId)}';
  }

  static String novelCover(String novelId) {
    return 'cover/novel/${_normalizePart(novelId)}';
  }

  static String comicPage({
    required String comicId,
    required String episodeId,
    required int imageIndex,
  }) {
    return 'comic/${_normalizePart(comicId)}/${_normalizePart(episodeId)}/${_padIndex(imageIndex)}';
  }

  static String novelInline({
    required String novelId,
    required String episodeId,
    required int imageIndex,
  }) {
    return 'novel/${_normalizePart(novelId)}/${_normalizePart(episodeId)}/${_padIndex(imageIndex)}';
  }

  static String customCover({
    required String ownerType,
    required String ownerId,
  }) {
    return 'cover/custom/${_normalizePart(ownerType)}/${_normalizePart(ownerId)}';
  }

  static String forumHeadImage(String sourceUrl) {
    return _normalizedUrlKey('forum/head_image', sourceUrl);
  }

  static String forumIcon(String sourceUrl) {
    return _normalizedUrlKey('forum/icon', sourceUrl);
  }

  static String threadInline(String sourceUrl) {
    return _normalizedUrlKey('thread/inline', sourceUrl);
  }

  static String threadAttachment(String sourceUrl) {
    return _normalizedUrlKey('thread/attachment', sourceUrl);
  }

  static String avatar(String sourceUrl) {
    return _normalizedUrlKey('avatar', sourceUrl);
  }

  static String blogInline(String sourceUrl) {
    return _normalizedUrlKey('blog/inline', sourceUrl);
  }

  static String remoteSmiley(String source) {
    final path = normalizeRemoteSmileyPath(source);
    final digest = _shortHash(path);
    return 'smiley/$digest/${_lastPathSegment(path)}';
  }

  static String normalizedUrl(String sourceUrl) {
    final value = sourceUrl.trim();
    if (value.isEmpty) {
      return '';
    }
    final uri = _resolveToUri(value);
    if (uri == null) {
      return value;
    }
    final queryParameters = Map<String, List<String>>.fromEntries(
      uri.queryParametersAll.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
    final normalizedQuery = <String, dynamic>{};
    for (final entry in queryParameters.entries) {
      final values = entry.value.toList()..sort();
      normalizedQuery[entry.key] = values.length == 1 ? values.single : values;
    }
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      path: _normalizePath(uri.path),
      queryParameters: normalizedQuery.isEmpty ? null : normalizedQuery,
    ).toString();
  }

  static String normalizeRemoteSmileyPath(String source) {
    final value = source.trim().replaceAll('\\', '/');
    if (value.isEmpty) {
      return 'unknown';
    }
    final uri = _resolveToUri(value);
    final path = uri?.path ?? value.split('?').first.split('#').first;
    final marker = '/static/image/smiley/';
    final lower = path.toLowerCase();
    final markerIndex = lower.indexOf(marker);
    final smileyPath = markerIndex >= 0
        ? path.substring(markerIndex + marker.length)
        : path.replaceFirst(RegExp(r'^/+'), '');
    final withoutPrefix = smileyPath.replaceFirst(
      RegExp(r'^(static/)?image/smiley/', caseSensitive: false),
      '',
    );
    return _normalizePath(withoutPrefix).replaceFirst(RegExp(r'^/+'), '');
  }

  static String _padIndex(int value) {
    final normalized = value < 0 ? 0 : value;
    return normalized.toString().padLeft(3, '0');
  }

  static String _normalizePart(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'unknown' : trimmed;
  }

  static String _normalizedUrlKey(String prefix, String sourceUrl) {
    final normalized = normalizedUrl(sourceUrl);
    final digest = _shortHash(normalized);
    return '$prefix/$digest/${_lastPathSegment(normalized)}';
  }

  static Uri? _resolveToUri(String value) {
    var source = value.trim();
    if (source.startsWith('//')) {
      source = 'https:$source';
    }
    var uri = Uri.tryParse(source);
    if (uri == null) {
      return null;
    }
    if (uri.scheme.isEmpty && uri.host.isEmpty) {
      final base = Uri.tryParse(AppConfig.siteBaseUrl);
      if (base == null) {
        return uri;
      }
      uri = base.resolve(source);
    }
    if (uri.scheme.isEmpty || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  static String _normalizePath(String path) {
    final segments = path
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(_safeDecodeComponent)
        .map(Uri.encodeComponent)
        .toList(growable: false);
    return '/${segments.join('/')}';
  }

  static String _safeDecodeComponent(String value) {
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return value;
    }
  }

  static String _shortHash(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash = (hash ^ byte) * 0x100000001b3;
      hash = hash.toUnsigned(64);
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String _lastPathSegment(String value) {
    final path = Uri.tryParse(value)?.path ?? value;
    final segments = path
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return 'image';
    }
    final segment = _safeDecodeComponent(segments.last).trim();
    return segment.isEmpty
        ? 'image'
        : segment.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }
}
