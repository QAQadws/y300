import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/core/network/yamibo/yamibo_resource_client.dart';

class ForumHomeCarouselImageProbe {
  ForumHomeCarouselImageProbe({
    required YamiboResourceClient resourceClient,
    required ImageRequestHeaderBuilder headerBuilder,
  })  : _resourceClient = resourceClient,
        _headerBuilder = headerBuilder;

  static const double fallbackAspectRatio = 3.45;
  static const Duration probeTimeout = Duration(seconds: 2);
  static const double _minReasonableAspectRatio = 2.4;
  static const double _maxReasonableAspectRatio = 5.2;

  final YamiboResourceClient _resourceClient;
  final ImageRequestHeaderBuilder _headerBuilder;

  Future<double?> resolveAspectRatio(
    String imageUrl,
  ) async {
    final cancelToken = CancelToken();
    final timeoutTimer = Timer(probeTimeout, () {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('carousel image probe timeout');
      }
    });
    try {
      final headers = await _headerBuilder.buildHeaders(imageUrl);
      final response = await _resourceClient.getBytes(
        url: imageUrl,
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.imageProbe,
          operation: 'forum.home.carouselProbe',
          pageKind: 'forum.home',
        ),
        headers: headers,
        cancelToken: cancelToken,
      );
      if (response case ApiFailure<List<int>>()) {
        return null;
      }
      final bytes = response.dataOrNull ?? const <int>[];
      if (bytes.isEmpty) {
        return null;
      }
      return _aspectRatioFromBytes(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    } finally {
      timeoutTimer.cancel();
    }
  }

  static double? _aspectRatioFromBytes(Uint8List bytes) {
    final size =
        _parsePngSize(bytes) ?? _parseJpegSize(bytes) ?? _parseWebpSize(bytes);
    if (size == null || size.width <= 0 || size.height <= 0) {
      return null;
    }
    return (size.width / size.height)
        .clamp(_minReasonableAspectRatio, _maxReasonableAspectRatio)
        .toDouble();
  }

  static _ImageSize? _parsePngSize(Uint8List bytes) {
    if (bytes.length < 24) {
      return null;
    }
    const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) {
        return null;
      }
    }
    final data = ByteData.sublistView(bytes);
    return _ImageSize(
      data.getUint32(16, Endian.big),
      data.getUint32(20, Endian.big),
    );
  }

  static _ImageSize? _parseJpegSize(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    var offset = 2;
    while (offset + 3 < bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      offset += 2;
      if (marker == 0xD9 || marker == 0xDA) {
        break;
      }
      if (offset + 1 >= bytes.length) {
        break;
      }
      final segmentLength = data.getUint16(offset, Endian.big);
      if (segmentLength < 2 || offset + segmentLength > bytes.length) {
        break;
      }
      if (_isJpegStartOfFrame(marker) && segmentLength >= 7) {
        final height = data.getUint16(offset + 3, Endian.big);
        final width = data.getUint16(offset + 5, Endian.big);
        return _ImageSize(width, height);
      }
      offset += segmentLength;
    }
    return null;
  }

  static bool _isJpegStartOfFrame(int marker) {
    return (marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF);
  }

  static _ImageSize? _parseWebpSize(Uint8List bytes) {
    if (bytes.length < 30 ||
        !_asciiEquals(bytes, 0, 'RIFF') ||
        !_asciiEquals(bytes, 8, 'WEBP')) {
      return null;
    }
    if (_asciiEquals(bytes, 12, 'VP8 ') && bytes.length >= 30) {
      final data = ByteData.sublistView(bytes);
      return _ImageSize(
        data.getUint16(26, Endian.little) & 0x3FFF,
        data.getUint16(28, Endian.little) & 0x3FFF,
      );
    }
    if (_asciiEquals(bytes, 12, 'VP8L') && bytes.length >= 25) {
      final b0 = bytes[21];
      final b1 = bytes[22];
      final b2 = bytes[23];
      final b3 = bytes[24];
      final width = 1 + (((b1 & 0x3F) << 8) | b0);
      final height = 1 + ((b3 << 6) | (b2 >> 2) | ((b1 & 0xC0) << 6));
      return _ImageSize(width, height);
    }
    if (_asciiEquals(bytes, 12, 'VP8X') && bytes.length >= 30) {
      final width = 1 + _readUint24Little(bytes, 24);
      final height = 1 + _readUint24Little(bytes, 27);
      return _ImageSize(width, height);
    }
    return null;
  }

  static bool _asciiEquals(Uint8List bytes, int offset, String text) {
    if (offset + text.length > bytes.length) {
      return false;
    }
    for (var index = 0; index < text.length; index++) {
      if (bytes[offset + index] != text.codeUnitAt(index)) {
        return false;
      }
    }
    return true;
  }

  static int _readUint24Little(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
  }
}

class _ImageSize {
  const _ImageSize(this.width, this.height);

  final int width;
  final int height;
}
