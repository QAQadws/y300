import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';

class MethodChannelReaderImageExportSink implements ReaderImageExportSink {
  MethodChannelReaderImageExportSink({
    required this.platform,
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.adws.y300/reader_image_export',
  );

  final ReaderImageExportPlatform platform;
  final MethodChannel _channel;

  @override
  Future<ReaderImageExportDestination> save({
    required String sourcePath,
    required String displayName,
    required String mimeType,
    String? albumName,
  }) async {
    try {
      final result = await _channel
          .invokeMethod<Map<Object?, Object?>>('saveImage', <String, Object?>{
            'sourcePath': sourcePath,
            'displayName': displayName,
            'mimeType': mimeType,
            'albumName': albumName,
          });
      final map = result?.map((key, value) => MapEntry(key.toString(), value));
      final locator = map?['locator'] as String?;
      final displayLocation = map?['displayLocation'] as String?;
      if (locator == null ||
          locator.isEmpty ||
          displayLocation == null ||
          displayLocation.isEmpty) {
        throw const ReaderImageExportException(
          ReaderImageExportFailureReason.mediaWriteFailed,
          'Platform export returned an invalid destination',
        );
      }
      return ReaderImageExportDestination(
        platform: platform,
        locator: locator,
        displayLocation: displayLocation,
      );
    } on PlatformException catch (error) {
      throw ReaderImageExportException(
        _reasonForPlatformCode(error.code),
        error.message,
      );
    } on MissingPluginException {
      throw const ReaderImageExportException(
        ReaderImageExportFailureReason.unsupportedPlatform,
      );
    }
  }

  ReaderImageExportFailureReason _reasonForPlatformCode(String code) {
    return switch (code) {
      'permissionDenied' => ReaderImageExportFailureReason.permissionDenied,
      'permissionRestricted' =>
        ReaderImageExportFailureReason.permissionRestricted,
      'unsupportedFormat' => ReaderImageExportFailureReason.unsupportedFormat,
      'unsupportedPlatform' =>
        ReaderImageExportFailureReason.unsupportedPlatform,
      _ => ReaderImageExportFailureReason.mediaWriteFailed,
    };
  }
}

class UnsupportedReaderImageExportSink implements ReaderImageExportSink {
  const UnsupportedReaderImageExportSink();

  @override
  Future<ReaderImageExportDestination> save({
    required String sourcePath,
    required String displayName,
    required String mimeType,
    String? albumName,
  }) {
    return Future<ReaderImageExportDestination>.error(
      const ReaderImageExportException(
        ReaderImageExportFailureReason.unsupportedPlatform,
      ),
    );
  }
}

ReaderImageExportSink createPlatformReaderImageExportSink() {
  if (kIsWeb) {
    return const UnsupportedReaderImageExportSink();
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return MethodChannelReaderImageExportSink(
      platform: ReaderImageExportPlatform.android,
    );
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return MethodChannelReaderImageExportSink(
      platform: ReaderImageExportPlatform.ios,
    );
  }
  return const UnsupportedReaderImageExportSink();
}
