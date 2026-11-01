import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/novel_inline_soft_space_profile.dart';
import '../../tool/novel_mixed_first_line_indent_profile.dart';

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
      orderedEquals(List.generate(14, (i) => i)),
    );
    for (final record in records) {
      final mode = record['mode']! as int;
      expect(record['passed'], isTrue);
      expect(record['direction'], mode.isOdd ? 'rtl' : 'ltr');
      expect(record['trimmed'], mode >= 2 && mode <= 5);
      expect(
        record['rows'],
        mode >= 2 && mode <= 5 || mode == 8 || mode == 9 ? 2 : 1,
      );
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

  test('mixed startup prepares real ruby, gaps and BR continuations', () {
    final records = profileMixedFirstLineIndents();
    expect(records.length, 8);
    expect(records.where((r) => r['readerFit'] == true).length, 4);
    for (final record in records) {
      expect(record['passed'], isTrue);
      expect(
        record['actualFirst'],
        closeTo(record['applied']! as double, .001),
      );
      expect(record['pages']! as int, greaterThanOrEqualTo(2));
      expect(record['baseGlyphs'], 7);
      expect(record['brContinuation'], isTrue);
      if (record['readerFit'] == true) {
        expect(record['advance'], 128);
        expect(record['passes'], inInclusiveRange(2, 3));
      }
      expect(record['warmBuilds'], 0);
      expect(record['warmPictures'], 0);
      expect(record['exitPins'], 0);
      expect(record['exitBytes'], 0);
      expect(utf8.encode(jsonEncode(record)).length, lessThanOrEqualTo(1000));
    }
  });

  test(
    'bundled indent checks native first/continuation rows and owner release',
    () {
      final records = profileFirstLineIndents();
      expect(records.length, 8);
      expect(records.where((r) => r['readerFit'] == true).length, 4);
      expect(records.map((r) => r['direction']).toSet(), {'ltr', 'rtl'});
      for (final record in records) {
        expect(record['passed'], isTrue);
        expect(
          record['actualFirst'],
          closeTo(record['applied']! as double, .001),
        );
        expect(record['actualContinuation'], closeTo(0, .001));
        expect(record['rows']! as int, greaterThan(1));
        expect(record['coldBuilds'], 1);
        if (record['readerFit'] == true) {
          expect(record['advance'], 128);
          expect(record['passes'], inInclusiveRange(2, 3));
        }
        expect(record['exitPins'], 0);
        expect(record['exitBytes'], 0);
        expect(utf8.encode(jsonEncode(record)).length, lessThanOrEqualTo(1000));
      }
      expect(profileFirstLineIndents(), records);
    },
  );
}
