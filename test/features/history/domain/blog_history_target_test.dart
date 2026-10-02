import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/domain/models/blog_history_target.dart';
import 'package:y300/features/history/domain/models/history_models.dart';

void main() {
  test('normalizes and round-trips the owner and blog identities', () {
    final target = BlogHistoryTarget(ownerUserId: ' 00101 ', blogId: '00023');

    expect(target.ownerUserId, '101');
    expect(target.blogId, '23');
    expect(target.encodedId, '101:23');
    expect(
      target.key,
      const HistoryTargetKey(type: HistoryTargetType.blog, id: '101:23'),
    );
    expect(BlogHistoryTarget.tryParse(target.encodedId)?.key, target.key);
    expect(BlogHistoryTarget.tryParse(' 00101 : 00023 ')?.key, target.key);
  });

  test('keeps large numeric identifiers without integer truncation', () {
    const id = '123456789012345678901234567890';
    final target = BlogHistoryTarget(ownerUserId: id, blogId: id);

    expect(BlogHistoryTarget.tryParse(target.encodedId)?.ownerUserId, id);
    expect(BlogHistoryTarget.tryParse(target.encodedId)?.blogId, id);
  });

  test('rejects incomplete, ambiguous and nonpositive identities', () {
    for (final value in ['', '0', '-1', '1.0', '+1', 'one', '1:2']) {
      expect(
        () => BlogHistoryTarget(ownerUserId: value, blogId: '23'),
        throwsFormatException,
      );
      expect(
        () => BlogHistoryTarget(ownerUserId: '101', blogId: value),
        throwsFormatException,
      );
    }
    for (final value in [
      '',
      '101',
      ':23',
      '101:',
      '0:23',
      '101:0',
      '-1:23',
      '101:one',
      '101:23:4',
    ]) {
      expect(BlogHistoryTarget.tryParse(value), isNull, reason: value);
    }
  });
}
