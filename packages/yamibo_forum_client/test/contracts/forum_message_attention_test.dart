import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

const unknown = ForumMessageAttentionState.unknown;
const absent = ForumMessageAttentionState.absent;
const present = ForumMessageAttentionState.present;

void main() {
  test('missing evidence cannot establish an inactive indicator', () {
    const observation = ForumMessageAttentionObservation(
      viewerUserId: 'viewer',
      source: ForumMessageAttentionSource.api,
    );
    expect(observation.combined, unknown);
    expect(observation.notificationCount, isNull);
  });

  test('a mobile aggregate does not fabricate individual categories', () {
    for (final state in [absent, present]) {
      final observation = ForumMessageAttentionObservation(
        viewerUserId: 'viewer',
        source: ForumMessageAttentionSource.mobileHtml,
        combinedHint: state,
      );
      expect(observation.combined, state);
      expect(observation.privateMessages, unknown);
      expect(observation.notifications, unknown);
    }
  });

  test(
    'partial absence stays unknown while either known positive is enough',
    () {
      for (final categories in [
        (absent, unknown, unknown),
        (unknown, absent, unknown),
        (absent, absent, absent),
        (present, unknown, present),
        (unknown, present, present),
        (present, absent, present),
      ]) {
        final observation = ForumMessageAttentionObservation(
          viewerUserId: 'viewer',
          source: ForumMessageAttentionSource.api,
          privateMessages: categories.$1,
          notifications: categories.$2,
        );
        expect(observation.combined, categories.$3);
      }
    },
  );

  test(
    'contradictory aggregate and categories cannot clear or create a hint',
    () {
      final observations = [
        const ForumMessageAttentionObservation(
          viewerUserId: 'viewer',
          source: ForumMessageAttentionSource.desktopHtml,
          combinedHint: absent,
          privateMessages: present,
        ),
        const ForumMessageAttentionObservation(
          viewerUserId: 'viewer',
          source: ForumMessageAttentionSource.desktopHtml,
          combinedHint: present,
          privateMessages: absent,
          notifications: absent,
        ),
      ];
      for (final observation in observations) {
        expect(observation.combined, unknown);
      }
    },
  );

  test('counts require explicit, consistent notification evidence', () {
    for (final count in [-1, 0, 3]) {
      expect(
        () => ForumMessageAttentionObservation(
          viewerUserId: 'viewer',
          source: ForumMessageAttentionSource.api,
          notificationCount: count,
        ),
        throwsA(isA<AssertionError>()),
      );
    }
    const zero = ForumMessageAttentionObservation(
      viewerUserId: 'viewer',
      source: ForumMessageAttentionSource.api,
      notifications: absent,
      notificationCount: 0,
    );
    expect(zero.notificationCount, 0);
    expect(zero.combined, unknown);
  });
}
