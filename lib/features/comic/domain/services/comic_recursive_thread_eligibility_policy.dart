import 'package:y300/features/thread/domain/thread_content_classifier.dart';

abstract interface class ComicRecursiveThreadEligibilityPolicy {
  bool allows({required String fid, required String typeid});
}

final class DefaultComicRecursiveThreadEligibilityPolicy
    implements ComicRecursiveThreadEligibilityPolicy {
  const DefaultComicRecursiveThreadEligibilityPolicy({
    ThreadContentClassifier classifier = const ThreadContentClassifier(),
  }) : _classifier = classifier;

  final ThreadContentClassifier _classifier;

  @override
  bool allows({required String fid, required String typeid}) {
    return _classifier.classify(fid: fid, typeid: typeid) ==
        ThreadContentKind.comic;
  }
}
