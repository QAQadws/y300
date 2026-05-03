import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/search/data/search_rate_limiter.dart';

void main() {
  group('SearchRateLimiter', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('allows first search when no history exists', () async {
      final limiter = SearchRateLimiter();

      final result = await limiter.check();

      expect(result.isAllowed, isTrue);
      expect(result.retryAfter, Duration.zero);
    });

    test('blocks repeated search within cooldown and returns remaining time', () async {
      final baseNow = DateTime(2026, 5, 3, 12, 0, 0);
      var now = baseNow;
      final limiter = SearchRateLimiter(
        cooldown: const Duration(seconds: 10),
        nowProvider: () => now,
      );

      await limiter.markTriggered();
      now = baseNow.add(const Duration(seconds: 3));
      final blocked = await limiter.check();

      expect(blocked.isAllowed, isFalse);
      expect(blocked.retryAfter.inSeconds, 7);
    });

    test('allows search again after cooldown', () async {
      final baseNow = DateTime(2026, 5, 3, 12, 0, 0);
      var now = baseNow;
      final limiter = SearchRateLimiter(
        cooldown: const Duration(seconds: 10),
        nowProvider: () => now,
      );

      await limiter.markTriggered();
      now = baseNow.add(const Duration(seconds: 11));
      final result = await limiter.check();

      expect(result.isAllowed, isTrue);
    });
  });
}

