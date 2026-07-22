import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_download_execution.dart';

void main() {
  test(
    'serializes concurrent network starts at one-second intervals',
    () async {
      var now = DateTime(2026, 7, 22, 12);
      final delays = <Duration>[];
      final governor = DefaultComicDownloadImageRequestGovernor(
        nowProvider: () => now,
        delay: (duration) async {
          delays.add(duration);
          now = now.add(duration);
        },
      );

      await Future.wait<void>(<Future<void>>[
        governor.waitForTurn(),
        governor.waitForTurn(),
        governor.waitForTurn(),
      ]);

      expect(delays, const <Duration>[
        Duration(seconds: 1),
        Duration(seconds: 1),
      ]);
    },
  );

  test('waits only for the missing part of the interval', () async {
    var now = DateTime(2026, 7, 22, 12);
    final delays = <Duration>[];
    final governor = DefaultComicDownloadImageRequestGovernor(
      nowProvider: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
    );

    await governor.waitForTurn();
    now = now.add(const Duration(milliseconds: 350));
    await governor.waitForTurn();
    now = now.add(const Duration(seconds: 2));
    await governor.waitForTurn();

    expect(delays, const <Duration>[Duration(milliseconds: 650)]);
  });
}
