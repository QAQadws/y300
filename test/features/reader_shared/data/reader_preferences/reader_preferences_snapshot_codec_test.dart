import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/data/reader_preferences/reader_preferences_snapshot_codec.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';

void main() {
  const codec = ReaderPreferencesSnapshotCodec();

  test('v1 snapshot round-trips all fields with stable enum names', () {
    const source = ReaderPreferences(
      readerMode: ReaderModePreference.rtl,
      pageFit: ReaderPageFitPreference.contain,
      background: ReaderBackgroundPreference.gray,
      pageSpacing: 7.5,
      showPageIndicator: false,
    );

    final encoded = codec.encode(source);
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    final decoded = codec.decode(encoded);

    expect(json['schemaVersion'], 1);
    expect(json['readerMode'], 'rtl');
    expect(json['pageFit'], 'contain');
    expect(json['background'], 'gray');
    expect(json['pageSpacing'], 7.5);
    expect(json['showPageIndicator'], isFalse);
    expect(decoded.readerMode, source.readerMode);
    expect(decoded.pageFit, source.pageFit);
    expect(decoded.background, source.background);
    expect(decoded.pageSpacing, source.pageSpacing);
    expect(decoded.showPageIndicator, source.showPageIndicator);
  });

  test('removed original fit migrates to contain in v1 snapshots', () {
    final decoded = codec.decode(
      jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'readerMode': 'rtl',
        'pageFit': 'original',
        'background': 'black',
        'pageSpacing': 0,
        'showPageIndicator': true,
      }),
    );

    expect(decoded.pageFit, ReaderPageFitPreference.contain);
  });

  test('supported page fits never encode the removed original value', () {
    for (final pageFit in ReaderPageFitPreference.values) {
      final encoded = codec.encode(
        ReaderPreferences.defaults().copyWith(pageFit: pageFit),
      );
      final json = jsonDecode(encoded) as Map<String, dynamic>;

      expect(json['pageFit'], isNot('original'));
    }
  });

  test('v1 snapshot normalizes invalid fields independently', () {
    final decoded = codec.decode(
      jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'readerMode': 'rtl',
        'pageFit': 'future-fit',
        'background': 'black',
        'pageSpacing': 99,
        'showPageIndicator': 'false',
      }),
    );

    expect(decoded.readerMode, ReaderModePreference.rtl);
    expect(decoded.pageFit, ReaderPageFitPreference.fitWidth);
    expect(decoded.background, ReaderBackgroundPreference.black);
    expect(decoded.pageSpacing, 48);
    expect(decoded.showPageIndicator, isTrue);
  });

  test('non-finite spacing is normalized before encoding', () {
    final encoded = codec.encode(
      ReaderPreferences.defaults().copyWith(pageSpacing: double.nan),
    );
    final decoded = codec.decode(encoded);

    expect(decoded.pageSpacing, ReaderPreferences.defaults().pageSpacing);
  });

  test('malformed and unsupported snapshots use one default snapshot', () {
    for (final source in <String?>[
      null,
      '',
      '{broken',
      '[]',
      jsonEncode(<String, Object>{'schemaVersion': 2, 'readerMode': 'rtl'}),
    ]) {
      final decoded = codec.decode(source);
      final defaults = ReaderPreferences.defaults();

      expect(decoded.readerMode, defaults.readerMode);
      expect(decoded.pageFit, defaults.pageFit);
      expect(decoded.background, defaults.background);
      expect(decoded.pageSpacing, defaults.pageSpacing);
      expect(decoded.showPageIndicator, defaults.showPageIndicator);
    }
  });
}
