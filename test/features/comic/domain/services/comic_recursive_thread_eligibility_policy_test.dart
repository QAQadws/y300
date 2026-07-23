import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_recursive_thread_eligibility_policy.dart';

void main() {
  group('DefaultComicRecursiveThreadEligibilityPolicy', () {
    const policy = DefaultComicRecursiveThreadEligibilityPolicy();

    test('accepts regular comic forum thread types', () {
      expect(policy.allows(fid: '30', typeid: '398'), isTrue);
      expect(policy.allows(fid: '30', typeid: '69'), isTrue);
    });

    test('rejects comic announcements and other forums', () {
      expect(policy.allows(fid: '30', typeid: '65'), isFalse);
      expect(policy.allows(fid: '49', typeid: '293'), isFalse);
      expect(policy.allows(fid: '55', typeid: '295'), isFalse);
      expect(policy.allows(fid: '', typeid: ''), isFalse);
    });

    test('keeps the existing classifier behavior for a blank typeid', () {
      expect(policy.allows(fid: '30', typeid: ''), isTrue);
    });
  });
}
