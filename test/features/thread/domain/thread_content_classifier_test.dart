import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  const classifier = ThreadContentClassifier();

  test('classifies comic and novel while excluding announcements', () {
    expect(
      classifier.classify(fid: '30', typeid: '65', tagName: '公告'),
      ThreadContentKind.forum,
    );
    expect(
      classifier.classify(fid: '30', typeid: '398'),
      ThreadContentKind.comic,
    );
    expect(
      classifier.classify(fid: '49', typeid: '121'),
      ThreadContentKind.forum,
    );
    expect(
      classifier.classify(fid: '49', typeid: '293'),
      ThreadContentKind.novel,
    );
    expect(
      classifier.classify(fid: '55', typeid: '147'),
      ThreadContentKind.forum,
    );
    expect(
      classifier.classify(fid: '55', typeid: '295'),
      ThreadContentKind.novel,
    );
    expect(classifier.classify(fid: '', typeid: ''), ThreadContentKind.unknown);
  });
}
