import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';

void main() {
  group('YamiboSessionStore', () {
    test('saves snapshot and returns fresh formhash', () {
      var now = DateTime(2026, 6, 19, 12);
      final store = YamiboSessionStore(now: () => now);

      store.saveExtracted(
        _snapshot(
          formhash: 'fh_1',
          uid: '123',
          username: 'tester',
          updatedAt: now,
        ),
      );

      expect(store.readCurrent()?.uid, '123');
      expect(store.readFreshFormhash(), 'fh_1');

      now = now.add(const Duration(minutes: 31));

      expect(store.readFreshFormhash(), isNull);
    });

    test(
      'does not overwrite existing formhash with an empty extracted value',
      () {
        final now = DateTime(2026, 6, 19, 12);
        final store = YamiboSessionStore(now: () => now);
        store.saveExtracted(
          _snapshot(
            formhash: 'fh_existing',
            uid: '123',
            username: 'tester',
            updatedAt: now,
          ),
        );

        store.saveExtracted(
          _snapshot(
            formhash: '',
            uid: '',
            username: '',
            updatedAt: now.add(const Duration(minutes: 1)),
            source: 'html:home',
          ),
        );

        final current = store.readCurrent();
        expect(current?.formhash, 'fh_existing');
        expect(current?.uid, '123');
        expect(current?.username, 'tester');
        expect(current?.source, 'html:home');
      },
    );

    test('clear removes current snapshot', () {
      final store = YamiboSessionStore();
      store.saveExtracted(
        _snapshot(
          formhash: 'fh',
          uid: '123',
          username: 'tester',
          updatedAt: DateTime(2026, 6, 19, 12),
        ),
      );

      store.clear();

      expect(store.readCurrent(), isNull);
      expect(store.readFreshFormhash(), isNull);
    });

    test('explicit guest uid can mark the session as logged out', () {
      final now = DateTime(2026, 6, 19, 12);
      final store = YamiboSessionStore(now: () => now);
      store.saveExtracted(
        _snapshot(
          formhash: 'fh_user',
          uid: '123',
          username: 'tester',
          updatedAt: now,
        ),
      );

      store.saveExtracted(
        _snapshot(
          formhash: 'fh_guest',
          uid: '0',
          username: '',
          updatedAt: now.add(const Duration(minutes: 1)),
          source: 'api:profile',
        ),
      );

      final current = store.readCurrent();
      expect(current?.isLoggedIn, isFalse);
      expect(current?.uid, '0');
      expect(current?.username, isEmpty);
      expect(current?.formhash, 'fh_guest');
    });
  });
}

YamiboSessionSnapshot _snapshot({
  required String formhash,
  required String uid,
  required String username,
  required DateTime updatedAt,
  String source = 'api:profile',
}) {
  return YamiboSessionSnapshot(
    isLoggedIn: uid.isNotEmpty && uid != '0',
    uid: uid,
    username: username,
    formhash: formhash,
    updatedAt: updatedAt,
    source: source,
  );
}
