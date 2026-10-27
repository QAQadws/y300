import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/services/favorite_membership_tracker.dart';

void main() {
  test('a lagging follow-up directory cannot contradict a newer confirmed relation', () {
    final tracker = FavoriteMembershipTracker();
    tracker.record('owner', {'200'}, favorited: true, id: 'new');
    final revision = tracker.revision;
    expect(tracker.conflicts('owner', {}), isTrue);
    expect(tracker.conflicts('owner', {'200': 'old'}), isTrue);
    expect(tracker.blocksRemote('owner', '200', 'old', revision), isTrue);
    expect(tracker.conflicts('owner', {'200': 'new'}), isFalse);
    tracker.acknowledge('owner', revision);
    expect(tracker.hasUnacknowledged('owner'), isFalse);
    expect(tracker.conflicts('owner', {}), isFalse);
    tracker.record('owner', {'200'}, favorited: false);
    tracker.record(
      'owner',
      {'200'},
      favorited: true,
      id: 'old',
      onlyIfUnknown: true,
    );
    expect(tracker.isUnfavorited('owner', '200'), isTrue);
  });

  test('acknowledged removals allow a later external favorite without accepting an obsolete job replay', () {
    final tracker = FavoriteMembershipTracker();
    tracker.record('owner', {'200'}, favorited: false);
    tracker.acknowledge('owner', tracker.revision);
    expect(tracker.isUnfavorited('owner', '200'), isTrue);
    tracker.observeDirectory('owner', tracker.revision, {
      '200': 'external',
    }, complete: true);
    expect(tracker.isUnfavorited('owner', '200'), isFalse);
    tracker.record(
      'owner',
      {'200'},
      favorited: true,
      id: 'old',
      onlyIfUnknown: true,
    );
    expect(tracker.hasUnacknowledged('owner'), isFalse);
    expect(
      tracker.blocksRemote('owner', '200', 'external', tracker.revision),
      isFalse,
    );
    expect(tracker.conflicts('different-owner', {'200': 'external'}), isFalse);
    tracker.record('owner', {'200'}, favorited: false);
    expect(tracker.isUnfavorited('owner', '200'), isTrue);
  });
}
