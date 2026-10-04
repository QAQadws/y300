import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_image_session_coordinator.dart';

void main() {
  test('ordinary rebuild keeps the opening token and generation', () {
    final sessions = ReaderImageSessionCoordinator();
    expect(sessions.current, isNull);
    expect(sessions.isCurrent(null), isFalse);
    final opening = sessions.activate(ownerId: 'chapter', revision: 4);
    final rebuild = sessions.activate(ownerId: 'chapter', revision: 4);
    expect(rebuild, same(opening));
    expect(sessions.generation, 1);
    expect(sessions.isCurrent(opening), isTrue);
  });

  test('same owner refresh retires the previous token', () {
    final sessions = ReaderImageSessionCoordinator();
    final opening = sessions.activate(ownerId: 'chapter', revision: 4);
    final refreshed = sessions.activate(ownerId: 'chapter', revision: 5);
    expect(refreshed.ownerId, 'chapter');
    expect(refreshed.revision, 5);
    expect(refreshed.generation, opening.generation + 1);
    expect(sessions.isCurrent(opening), isFalse);
    expect(sessions.isCurrent(refreshed), isTrue);
  });

  test(
    'returning to the same owner and revision cannot revive its old token',
    () {
      final sessions = ReaderImageSessionCoordinator();
      final opening = sessions.activate(ownerId: 'chapter', revision: 4);
      final next = sessions.activate(ownerId: 'next', revision: 0);
      final reopened = sessions.activate(ownerId: 'chapter', revision: 4);
      expect(reopened, isNot(same(opening)));
      expect(reopened.generation, next.generation + 1);
      expect(sessions.isCurrent(opening), isFalse);
      expect(sessions.isCurrent(next), isFalse);
      expect(sessions.isCurrent(reopened), isTrue);
    },
  );

  test('closing invalidates callbacks and cannot reopen a disposed engine', () {
    final sessions = ReaderImageSessionCoordinator();
    final opening = sessions.activate(ownerId: 'chapter', revision: 4);
    sessions.close();
    sessions.close();
    expect(sessions.isCurrent(opening), isFalse);
    expect(
      () => sessions.activate(ownerId: 'chapter', revision: 4),
      throwsStateError,
    );
  });
}
