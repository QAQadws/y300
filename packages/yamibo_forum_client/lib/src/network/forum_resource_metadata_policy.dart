import 'dart:convert';

/// Pure image metadata decisions shared by package and Host transports.
///
/// This helper does not send requests, consume streams, decode images, or manage
/// Cookies. A declared image MIME type remains sufficient for the transport's
/// direct-stream path; signature checks apply when a prefix is already available.
abstract final class ForumResourceMetadataPolicy {
  static const Duration _defaultLifetime = Duration(days: 7);

  /// Whether [contentType] declares an image, ignoring case and MIME parameters.
  ///
  /// Unknown `image/*` subtypes are accepted, matching the existing transport
  /// boundary. This does not prove that the bytes can be decoded by a Host.
  static bool hasDeclaredImageContentType(String? contentType) {
    final mime = contentType?.split(';').first.trim().toLowerCase();
    return mime?.startsWith('image/') == true;
  }

  /// Whether an already available [prefix] or [contentType] identifies an image.
  ///
  /// A recognized signature can override a misleading non-image MIME type.
  /// This method does not fetch additional bytes or validate a complete image.
  static bool isSupportedImage(String? contentType, List<int> prefix) =>
      _signatureExtension(prefix).isNotEmpty ||
      hasDeclaredImageContentType(contentType);

  /// Chooses a dotted extension from [signature], [contentType], then [uri].
  ///
  /// Unknown extensions return an empty string. URI fallback accepts one to five
  /// ASCII letters or digits; it is naming metadata, not image validation.
  static String imageFileExtension(
    String? contentType,
    Uri uri, {
    List<int>? signature,
  }) {
    final fromSignature = signature == null
        ? ''
        : _signatureExtension(signature);
    if (fromSignature.isNotEmpty) return fromSignature;
    final mime = contentType?.split(';').first.trim().toLowerCase();
    final fromMime = switch (mime) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'image/avif' => '.avif',
      'image/svg+xml' => '.svg',
      'image/bmp' => '.bmp',
      'image/x-icon' || 'image/vnd.microsoft.icon' => '.ico',
      _ => '',
    };
    if (fromMime.isNotEmpty) return fromMime;
    final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = segment.lastIndexOf('.');
    if (dot < 0) return '';
    final extension = segment.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension) ? extension : '';
  }

  /// Computes the existing image cache lifetime without reading the clock.
  ///
  /// Defaults to seven days. Only the first value of the first nonempty
  /// case-insensitive `Cache-Control` header entry is read. Recognized directives
  /// update the lifetime in response order: a later valid `max-age` can override
  /// an earlier `no-cache` or `no-store`. This intentionally characterizes the
  /// existing transports; it does not implement HTTP cache directive precedence.
  /// Invalid or negative ages are ignored, and quoted ages are not parsed.
  static Duration cacheLifetime(Map<String, List<String>> headers) {
    var lifetime = _defaultLifetime;
    final cacheControl = _firstHeader(headers, 'cache-control');
    if (cacheControl != null) {
      for (final setting in cacheControl.split(',')) {
        final value = setting.trim().toLowerCase();
        if (value == 'no-cache' || value == 'no-store') {
          lifetime = Duration.zero;
        } else if (value.startsWith('max-age=')) {
          final seconds = int.tryParse(value.substring('max-age='.length));
          if (seconds != null && seconds >= 0) {
            lifetime = Duration(seconds: seconds);
          }
        }
      }
    }
    return lifetime;
  }

  static String? _firstHeader(Map<String, List<String>> headers, String name) {
    final expected = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == expected && entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  static String _signatureExtension(List<int> bytes) {
    bool starts(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (var index = 0; index < signature.length; index += 1) {
        if (bytes[index] != signature[index]) return false;
      }
      return true;
    }

    if (starts(const <int>[0xff, 0xd8, 0xff])) return '.jpg';
    if (starts(const <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
      return '.png';
    }
    if (starts(const <int>[0x47, 0x49, 0x46, 0x38])) return '.gif';
    if (starts(const <int>[0x42, 0x4d])) return '.bmp';
    if (starts(const <int>[0x00, 0x00, 0x01, 0x00])) return '.ico';
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return '.webp';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp') {
      final brand = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
      if (brand == 'avif' || brand == 'avis') return '.avif';
      if (const <String>{
        'heic',
        'heix',
        'hevc',
        'hevx',
        'mif1',
        'msf1',
      }.contains(brand)) {
        return '.heic';
      }
    }
    final text = utf8
        .decode(bytes.take(1024).toList(growable: false), allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    return text.startsWith('<svg') ||
            (text.startsWith('<?xml') && text.contains('<svg'))
        ? '.svg'
        : '';
  }
}
