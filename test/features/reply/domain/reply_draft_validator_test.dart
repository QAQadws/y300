import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/reply_draft_validator.dart';

void main() {
  group('ReplyDraftValidator', () {
    const validator = ReplyDraftValidator();

    ReplyDraft draftWithMessage(String message) {
      return ReplyDraft(fid: '33', tid: '572063', message: message);
    }

    test('rejects empty message', () {
      final result = validator.validate(draftWithMessage(''));

      expect(result.isValid, isFalse);
      expect(result.code, ReplyValidationCode.emptyMessage);
    });

    test('rejects whitespace only message', () {
      final result = validator.validate(draftWithMessage('   \n\t  '));

      expect(result.isValid, isFalse);
      expect(result.code, ReplyValidationCode.emptyMessage);
    });

    test('accepts plain text message', () {
      final result = validator.validate(draftWithMessage('这是测试回复'));

      expect(result.isValid, isTrue);
      expect(result.code, isNull);
    });

    test('accepts bbcode message', () {
      final result = validator.validate(
        draftWithMessage('[quote]引用[/quote]\n[b]正文[/b]'),
      );

      expect(result.isValid, isTrue);
      expect(result.code, isNull);
    });
  });
}
