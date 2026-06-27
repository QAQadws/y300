import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/services/library_work_freshness_policy.dart';

void main() {
  test('shouldCheck requests missing or stale source metadata checks', () {
    const policy = LibraryWorkFreshnessPolicy(
      checkInterval: Duration(hours: 24),
    );
    final now = DateTime(2026, 6, 27, 12);

    expect(policy.shouldCheck(lastCheckedAt: null, now: now), isTrue);
    expect(
      policy.shouldCheck(
        lastCheckedAt: now.subtract(const Duration(hours: 23)),
        now: now,
      ),
      isFalse,
    );
    expect(
      policy.shouldCheck(
        lastCheckedAt: now.subtract(const Duration(hours: 24)),
        now: now,
      ),
      isTrue,
    );
    expect(
      policy.shouldCheck(
        lastCheckedAt: now.add(const Duration(minutes: 1)),
        now: now,
      ),
      isFalse,
    );
  });
}
