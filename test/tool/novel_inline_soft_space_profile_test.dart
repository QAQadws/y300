import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/novel_inline_soft_space_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // FlutterTester does not register bundled custom fonts. Actual profile
    // startup deliberately has no loader and must use the package manifest.
    await (FontLoader('packages/forum_content_renderer/ForumBodyInlineSpace')
          ..addFont(
            rootBundle.load(
              'packages/forum_content_renderer/assets/fonts/inline_space.ttf',
            ),
          ))
        .load();
  });

  test('startup coverage checks both directions, trim and warm owner release', () {
    final records = profileInlineSoftSpaces();
    expect(
      records.map((r) => r['mode']),
      orderedEquals(List.generate(10, (i) => i)),
    );
    for (final record in records) {
      final mode = record['mode']! as int;
      expect(record['passed'], isTrue);
      expect(record['direction'], mode.isOdd ? 'rtl' : 'ltr');
      expect(record['trimmed'], mode >= 2 && mode <= 5);
      expect(record['rows'], mode >= 2 && mode <= 5 || mode >= 8 ? 2 : 1);
      expect(record['coldBuilds'], 1);
      expect(record['warmBuilds'], 0);
      expect(record['exitPins'], 0);
      expect(record['exitBytes'], 0);
      if (mode == 4 || mode == 5) {
        expect(record['height'], records[mode - 2]['height']);
      }
      expect(utf8.encode(jsonEncode(record)).length, lessThanOrEqualTo(1000));
    }
    expect(() => records.clear(), throwsUnsupportedError);
    expect(() => records.first['passed'] = false, throwsUnsupportedError);
    // A second run gets new owners; previous cleanup must not retire the engine
    // resource or accidentally provide the next run's cold native layout.
    expect(profileInlineSoftSpaces(), records);
  });
}
