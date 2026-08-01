import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';

void main() {
  group('ComposerAttachBbCodeService', () {
    const service = ComposerAttachBbCodeService();

    test('builds attach code', () {
      expect(service.attachCode(' 123456 '), '[attach]123456[/attach]');
    });

    test('appends multiple aids in order on separate lines', () {
      expect(
        service.appendAttachCodes('正文', ['123', '456']),
        '正文\n[attach]123[/attach]\n[attach]456[/attach]',
      );
    });

    test(
      'appends without extra newline when message already ends with newline',
      () {
        expect(
          service.appendAttachCodes('正文\n', ['123']),
          '正文\n[attach]123[/attach]',
        );
      },
    );

    test('filters blank aids', () {
      expect(
        service.appendAttachCodes('', ['123', ' ', '456']),
        '[attach]123[/attach]\n[attach]456[/attach]',
      );
    });

    test('removes matching exclusive attach lines only', () {
      const message =
          '开头\n'
          '[attach]123[/attach]\n'
          '正文 [attach]123[/attach]\n'
          '[attach]456[/attach]\n'
          '结尾';

      expect(
        service.removeAttachCodes(message, ['123']),
        '开头\n正文 [attach]123[/attach]\n[attach]456[/attach]\n结尾',
      );
    });

    test('keeps unknown attach lines and ordinary text', () {
      const message = '开头\n[attach]123[/attach]\n结尾';

      expect(service.removeAttachCodes(message, ['999']), message);
    });

    test('extracts a single attach aid', () {
      expect(service.extractAttachAids('正文\n[attach]123[/attach]'), ['123']);
    });

    test('extracts multiple attach aids in source order', () {
      expect(
        service.extractAttachAids(
          '[attach]123[/attach]\n正文\n[attach]456[/attach]',
        ),
        ['123', '456'],
      );
    });

    test('filters blank attach aids', () {
      expect(
        service.extractAttachAids('[attach]   [/attach]\n[attach]123[/attach]'),
        ['123'],
      );
    });

    test('extracts attach aids with case insensitive tags', () {
      expect(service.extractAttachAids('[ATTACH]123[/Attach]'), ['123']);
    });

    test('does not treat ordinary text or sticker code as attach aid', () {
      expect(service.extractAttachAids('正文{:9_656:}[b]粗体[/b]'), isEmpty);
    });
  });
}
