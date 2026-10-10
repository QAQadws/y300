import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reader requests plain text once and preserves its original content',
    () async {
      final calls = <MethodCall>[];
      const text = '分享 😀\n https://bbs.yamibo.com/thread-123-2-1.html ';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return {'text': text};
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(clipboardTextReaderProvider).readText(),
        text,
      );
      expect(calls, hasLength(1));
      expect(calls.single.method, 'Clipboard.getData');
      expect(calls.single.arguments, Clipboard.kTextPlain);
      expect(
        container.read(clipboardSelfCopyFingerprintRegistryProvider).length,
        0,
      );
    },
  );

  test('clipboard with no textual value is represented as null', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(clipboardTextReaderProvider).readText(),
      isNull,
    );
  });

  test('platform access failure remains observable by the host', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async {
      throw PlatformException(code: 'not_available');
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await expectLater(
      container.read(clipboardTextReaderProvider).readText(),
      throwsA(isA<PlatformException>()),
    );
  });
}
