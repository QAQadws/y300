import 'package:flutter_test/flutter_test.dart';

import '../../tool/novel_pagination_profile_config.dart';

void main() {
  test('defaults express both fixtures and all required baseline counts', () {
    const config = NovelProfileBaselineConfig();
    config.validate();
    expect(config.hasRequiredSampleCounts, isTrue);
    bool complete(int warmups, int opens, List<int> turns) =>
        profileBaselineCompleted(
          config: config,
          successfulWarmups: warmups,
          successfulOpens: opens,
          completedTurns: turns,
        );
    expect(complete(10, 60, [200, 200, 200]), isTrue);
    expect(complete(9, 60, [200, 200, 200]), isFalse);
    expect(complete(10, 59, [200, 200, 200]), isFalse);
    expect(complete(10, 60, [200, 200]), isFalse);
    expect(complete(10, 60, [200, 199, 200]), isFalse);
  });

  test('small smoke samples cannot be mistaken for the S0 sample size', () {
    const config = NovelProfileBaselineConfig(
      warmupsPerFixture: 1,
      opensPerFixture: 1,
      turnGroups: 1,
      turnsPerGroup: 2,
    );
    config.validate();
    expect(config.hasRequiredSampleCounts, isFalse);
    expect(config.toJson()['hasRequiredSampleCounts'], isFalse);
    expect(
      profileBaselineCompleted(
        config: config,
        successfulWarmups: 2,
        successfulOpens: 2,
        completedTurns: [2],
      ),
      isTrue,
    );
    expect(
      const NovelProfileBaselineConfig(opensPerFixture: 0).validate,
      throwsArgumentError,
    );
    expect(
      const NovelProfileBaselineConfig(turnsPerGroup: -1).validate,
      throwsArgumentError,
    );
  });

  test('long turn series bounce inside the completed chapter', () {
    for (final pages in [2, 3, 14]) {
      var current = 0;
      var forward = true;
      final visited = <int>{};
      for (var i = 0; i < 600; i++) {
        final target = nextProfileTurn(
          currentPage: current,
          pageCount: pages,
          forward: forward,
        )!;
        expect((target.page - current).abs(), 1);
        expect(target.page, inInclusiveRange(0, pages - 1));
        visited.add(target.page);
        current = target.page;
        forward = target.forward;
      }
      expect(visited, containsAll([0, pages - 1]));
    }
    expect(
      nextProfileTurn(currentPage: 0, pageCount: 1, forward: true),
      isNull,
    );
    expect(
      () => nextProfileTurn(currentPage: 2, pageCount: 2, forward: true),
      throwsArgumentError,
    );
  });
}
