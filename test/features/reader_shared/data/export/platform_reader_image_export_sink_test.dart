import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/data/export/platform_reader_image_export_sink.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('y300.test/reader_image_export');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps a platform destination without exposing a private path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'saveImage');
          expect(call.arguments, <String, Object?>{
            'sourcePath': 'cache/original.jpg',
            'displayName': 'page-1.jpg',
            'mimeType': 'image/jpeg',
            'albumName': 'Y300',
          });
          return <String, Object?>{
            'locator': 'content://media/external/images/1',
            'displayLocation': 'Pictures/Y300/page-1.jpg',
          };
        });
    final sink = MethodChannelReaderImageExportSink(
      platform: ReaderImageExportPlatform.android,
      channel: channel,
    );

    final destination = await sink.save(
      sourcePath: 'cache/original.jpg',
      displayName: 'page-1.jpg',
      mimeType: 'image/jpeg',
      albumName: 'Y300',
    );

    expect(destination.platform, ReaderImageExportPlatform.android);
    expect(destination.locator, 'content://media/external/images/1');
    expect(destination.displayLocation, 'Pictures/Y300/page-1.jpg');
  });

  test('preserves the iOS PhotoKit asset identifier', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object?>{
            'locator': '73A2/L0/001',
            'displayLocation': '系统照片',
          };
        });
    final sink = MethodChannelReaderImageExportSink(
      platform: ReaderImageExportPlatform.ios,
      channel: channel,
    );

    final destination = await sink.save(
      sourcePath: 'cache/original.png',
      displayName: 'page-1.png',
      mimeType: 'image/png',
    );

    expect(destination.platform, ReaderImageExportPlatform.ios);
    expect(destination.locator, '73A2/L0/001');
    expect(destination.displayLocation, '系统照片');
  });

  test('maps permission errors to a stable domain reason', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'permissionDenied',
            message: 'denied',
          );
        });
    final sink = MethodChannelReaderImageExportSink(
      platform: ReaderImageExportPlatform.ios,
      channel: channel,
    );

    expect(
      () => sink.save(
        sourcePath: 'cache/original.png',
        displayName: 'page-1.png',
        mimeType: 'image/png',
      ),
      throwsA(
        isA<ReaderImageExportException>().having(
          (error) => error.reason,
          'reason',
          ReaderImageExportFailureReason.permissionDenied,
        ),
      ),
    );
  });

  test('maps a missing platform implementation to unsupportedPlatform', () {
    final sink = MethodChannelReaderImageExportSink(
      platform: ReaderImageExportPlatform.android,
      channel: channel,
    );

    expect(
      () => sink.save(
        sourcePath: 'cache/original.webp',
        displayName: 'page-1.webp',
        mimeType: 'image/webp',
      ),
      throwsA(
        isA<ReaderImageExportException>().having(
          (error) => error.reason,
          'reason',
          ReaderImageExportFailureReason.unsupportedPlatform,
        ),
      ),
    );
  });
}
