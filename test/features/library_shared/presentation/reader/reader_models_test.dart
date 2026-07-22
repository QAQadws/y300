import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';

void main() {
  test('ReaderChromeInsets combines chrome and system safe area insets', () {
    const insets = ReaderChromeInsets(
      top: 8,
      bottom: 12,
      safeAreaTop: 24,
      safeAreaBottom: 30,
    );

    expect(insets.topInset, 32);
    expect(insets.persistentBottomInset, 42);
    expect(insets.bottomInset, 42);
  });

  test('ReaderChromeInsets equality includes both safe area edges', () {
    const base = ReaderChromeInsets(safeAreaTop: 24, safeAreaBottom: 30);

    expect(base, const ReaderChromeInsets(safeAreaTop: 24, safeAreaBottom: 30));
    expect(base, isNot(const ReaderChromeInsets(safeAreaTop: 23)));
    expect(base, isNot(const ReaderChromeInsets(safeAreaBottom: 29)));
  });
}
