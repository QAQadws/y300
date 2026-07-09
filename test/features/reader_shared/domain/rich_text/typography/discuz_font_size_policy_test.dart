import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/discuz_font_size_policy.dart';

void main() {
  test('maps Discuz size 3 to the normal body size', () {
    expect(DiscuzFontSizePolicy.cssPercentFor('3'), '100%');
    expect(DiscuzFontSizePolicy.fontSizeForBase(3, baseFontSize: 16), 16);
  });

  test('maps all Discuz editor sizes to fixed scales', () {
    expect(DiscuzFontSizePolicy.cssPercentFor('1'), '75%');
    expect(DiscuzFontSizePolicy.cssPercentFor('2'), '87.5%');
    expect(DiscuzFontSizePolicy.cssPercentFor('4'), '112.5%');
    expect(DiscuzFontSizePolicy.cssPercentFor('5'), '125%');
    expect(DiscuzFontSizePolicy.cssPercentFor('6'), '150%');
    expect(DiscuzFontSizePolicy.cssPercentFor('7'), '175%');
  });

  test('rejects invalid sizes', () {
    expect(DiscuzFontSizePolicy.normalize('0'), isNull);
    expect(DiscuzFontSizePolicy.normalize('8'), isNull);
    expect(DiscuzFontSizePolicy.normalize('large'), isNull);
  });
}
