import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/core/clipboard/self_copy_fingerprint_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('records success only after the platform completes its write', () async {
    final registry = SelfCopyFingerprintRegistry();
    final completion = Completer<void>();
    final writes = <String>[];
    final writer = PlatformClipboardTextWriter(
      selfCopyRegistry: registry,
      platformWrite: (text) {
        writes.add(text);
        return completion.future;
      },
    );
    const text = '  分享 😀 https://bbs.yamibo.com/thread-123-2-1.html#pid456\n';

    final write = writer.writeText(text);
    expect(writes, [text]);
    expect(registry.containsText(text), isFalse);
    completion.complete();
    await write;
    expect(registry.containsText(text), isTrue);
    expect(registry.length, 1);
  });

  test(
    'a failed write is propagated and does not become self-copy evidence',
    () async {
      final registry = SelfCopyFingerprintRegistry()
        ..recordSuccessfulWrite('previous');
      final failure = PlatformException(code: 'write_failed');
      final writer = PlatformClipboardTextWriter(
        selfCopyRegistry: registry,
        platformWrite: (_) => Future<void>.error(failure),
      );

      await expectLater(writer.writeText('new'), throwsA(same(failure)));
      expect(registry.length, 1);
      expect(registry.containsText('previous'), isTrue);
      expect(registry.containsText('new'), isFalse);
    },
  );

  test(
    'pending writes are recorded in completion order, with bounded capacity',
    () async {
      final registry = SelfCopyFingerprintRegistry(capacity: 2);
      final completions = <String, Completer<void>>{};
      final writer = PlatformClipboardTextWriter(
        selfCopyRegistry: registry,
        platformWrite: (text) {
          final completion = Completer<void>();
          completions[text] = completion;
          return completion.future;
        },
      );
      final first = writer.writeText('first');
      final second = writer.writeText('second');
      final third = writer.writeText('third');

      completions['second']!.complete();
      await second;
      completions['first']!.complete();
      await first;
      completions['third']!.complete();
      await third;

      expect(registry.length, 2);
      expect(registry.containsText('second'), isFalse);
      expect(registry.containsText('first'), isTrue);
      expect(registry.containsText('third'), isTrue);
    },
  );

  test(
    'production providers share the registry and write once without reading',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        if (call.method != 'Clipboard.setData') {
          fail('Unexpected platform call: ${call.method}');
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const text = '正文原文\nhttps://bbs.yamibo.com/thread-1-1-1.html';

      await container.read(clipboardTextWriterProvider).writeText(text);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'Clipboard.setData');
      expect(calls.single.arguments, {'text': text});
      final registry = container.read(
        clipboardSelfCopyFingerprintRegistryProvider,
      );
      expect(registry.containsText(text), isTrue);
      expect(
        identical(
          registry,
          container.read(clipboardSelfCopyFingerprintRegistryProvider),
        ),
        isTrue,
      );
      final freshContainer = ProviderContainer();
      addTearDown(freshContainer.dispose);
      expect(
        freshContainer
            .read(clipboardSelfCopyFingerprintRegistryProvider)
            .length,
        0,
      );
    },
  );
}
