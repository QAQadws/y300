import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_image_layout_hint.dart';

void main() {
  group('ThreadPostBlockImageLayoutHint value equality', () {
    test('equal hints share same hashCode', () {
      const a = ThreadPostBlockImageLayoutHint(
        aspectRatio: 1.5,
        source: ThreadPostResourceLayoutHintSource.htmlAttribute,
      );
      const b = ThreadPostBlockImageLayoutHint(
        aspectRatio: 1.5,
        source: ThreadPostResourceLayoutHintSource.htmlAttribute,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differ on aspectRatio', () {
      const a = ThreadPostBlockImageLayoutHint(
        aspectRatio: 1.0,
        source: ThreadPostResourceLayoutHintSource.contentDefault,
      );
      const b = ThreadPostBlockImageLayoutHint(
        aspectRatio: 1.5,
        source: ThreadPostResourceLayoutHintSource.contentDefault,
      );
      expect(a, isNot(equals(b)));
    });
  });
}
