import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reply/domain/services/reply_attach_bbcode_service.dart';

void main() {
  group('ReplyAttachBbCodeService', () {
    const service = ReplyAttachBbCodeService();

    test('builds attach code', () {
      expect(service.attachCode(' 123456 '), '[attach]123456[/attach]');
    });

    test('appends multiple aids in order on separate lines', () {
      expect(
        service.appendAttachCodes('正文', ['123', '456']),
        '正文\n[attach]123[/attach]\n[attach]456[/attach]',
      );
    });

    test('appends without extra newline when message already ends with newline', () {
      expect(
        service.appendAttachCodes('正文\n', ['123']),
        '正文\n[attach]123[/attach]',
      );
    });

    test('filters blank aids', () {
      expect(
        service.appendAttachCodes('', ['123', ' ', '456']),
        '[attach]123[/attach]\n[attach]456[/attach]',
      );
    });

    test('removes matching exclusive attach lines only', () {
      const message = '开头\n'
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
  });
}
