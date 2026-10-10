import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/clipboard/self_copy_fingerprint_registry.dart';

void main() {
  test(
    'keeps a bounded recent-write registry and evicts the oldest evidence',
    () {
      final registry = SelfCopyFingerprintRegistry();
      for (var index = 0; index < 21; index++) {
        registry.recordSuccessfulWrite(
          'https://bbs.yamibo.com/thread-$index-1-1.html',
        );
      }

      expect(registry.length, 20);
      expect(
        registry.containsText('https://bbs.yamibo.com/thread-0-1-1.html'),
        isFalse,
      );
      expect(
        registry.containsText('https://bbs.yamibo.com/thread-1-1-1.html'),
        isTrue,
      );
      expect(
        registry.containsText('https://bbs.yamibo.com/thread-20-1-1.html'),
        isTrue,
      );
    },
  );

  test(
    'successful repeated writes refresh evidence without duplicate slots',
    () {
      final registry = SelfCopyFingerprintRegistry(capacity: 2);
      registry
        ..recordSuccessfulWrite('first')
        ..recordSuccessfulWrite('second')
        ..recordSuccessfulWrite('first')
        ..recordSuccessfulWrite('third');

      expect(registry.length, 2);
      expect(registry.containsText('first'), isTrue);
      expect(registry.containsText('second'), isFalse);
      expect(registry.containsText('third'), isTrue);
    },
  );

  test(
    'lookups do not renew evidence and compare the entire original text',
    () {
      final registry = SelfCopyFingerprintRegistry(capacity: 2);
      const text = '分享 😀 https://bbs.yamibo.com/thread-123-2-1.html#pid456\n';
      registry
        ..recordSuccessfulWrite(text)
        ..recordSuccessfulWrite('second');

      expect(registry.containsText(text), isTrue);
      expect(registry.containsText(text.trim()), isFalse);
      expect(registry.containsText(text.replaceFirst('😀', '😃')), isFalse);
      registry.recordSuccessfulWrite('third');
      expect(registry.containsText(text), isFalse);
    },
  );

  test('fresh registries do not retain evidence from previous instances', () {
    final oldRegistry = SelfCopyFingerprintRegistry()
      ..recordSuccessfulWrite('https://bbs.yamibo.com/thread-1-1-1.html');

    expect(oldRegistry.length, 1);
    expect(SelfCopyFingerprintRegistry().length, 0);
  });

  test('rejects a non-positive capacity', () {
    expect(() => SelfCopyFingerprintRegistry(capacity: 0), throwsArgumentError);
    expect(
      () => SelfCopyFingerprintRegistry(capacity: -1),
      throwsArgumentError,
    );
  });
}
