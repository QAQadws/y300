import 'dart:io';
import 'dart:typed_data';

Uint8List loadTestFont({int variant = 1}) {
  if (variant != 1 && variant != 2) {
    throw ArgumentError.value(variant, 'variant');
  }
  return File(
    'test/features/fonts/test_support/material_icons_subset_$variant.ttf',
  ).readAsBytesSync();
}

Uint8List loadTestCffFont() =>
    File('test/features/fonts/test_support/flutter_test_cff.otf')
        .readAsBytesSync();
