import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

void main() {
  group('RuleBasedComicDetector', () {
    test('returns candidate when strong signals are met', () {
      final detector = RuleBasedComicDetector();
      final result = detector.detect(
        fid: '30',
        subject: '【某某汉化组】第12话',
        message: '<img src="a.jpg"/><img src="b.jpg"/><a href="thread-100-1-1.html">1</a><a href="thread-101-1-1.html">2</a>',
      );

      expect(result.isCandidate, isTrue);
      expect(result.score, greaterThanOrEqualTo(60));
    });

    test('returns non-candidate when weak signals only', () {
      final detector = RuleBasedComicDetector();
      final result = detector.detect(
        fid: '2',
        subject: '普通讨论帖',
        message: '<p>今天聊聊天，目录在置顶。</p>',
      );

      expect(result.isCandidate, isFalse);
      expect(result.score, lessThan(60));
    });
  });
}
