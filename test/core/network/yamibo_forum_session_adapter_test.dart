import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_client_host_adapters.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart' as forum;

void main() {
  test(
    'package session projection is persisted through the Host port',
    () async {
      final store = YamiboSessionStore();
      final adapter = Y300ForumSessionAdapter(store);
      final updatedAt = DateTime.utc(2026, 8, 30, 12);

      await adapter.merge(
        forum.ForumSessionSnapshot(
          isLoggedIn: true,
          userId: '30001',
          username: 'fixture-user',
          formhash: 'fixture-formhash',
          updatedAt: updatedAt,
          source: 'api:profile',
          formhashUpdatedAt: updatedAt,
        ),
      );

      expect(store.readCurrent()?.uid, '30001');
      expect(store.readCurrent()?.username, 'fixture-user');
      expect(store.readFreshFormhash(), 'fixture-formhash');
      expect(adapter.readCurrent()?.source, 'api:profile');
    },
  );
}
