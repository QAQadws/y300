import 'package:y300/core/network/api_result.dart';

class YamiboResourceStreamResponse {
  const YamiboResourceStreamResponse({
    required this.uri,
    required this.statusCode,
    required this.content,
    required this.validUntil,
    this.contentLength,
    this.contentType,
    this.eTag,
    this.fileExtension = '',
  });

  final Uri uri;
  final int statusCode;
  final Stream<List<int>> content;
  final int? contentLength;
  final String? contentType;
  final String? eTag;
  final DateTime validUntil;
  final String fileExtension;
}

class YamiboResourceStreamException implements Exception {
  const YamiboResourceStreamException({
    required this.error,
    required this.bytesReceived,
  });

  final ApiError error;
  final int bytesReceived;
}
