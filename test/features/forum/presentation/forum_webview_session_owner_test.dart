import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_session_owner.dart';

YamiboSessionSnapshot _snapshot(String uid, {String formhash = 'proof'}) =>
    YamiboSessionSnapshot(
      isLoggedIn: uid != '0',
      uid: uid,
      username: uid == '0' ? '' : 'user-$uid',
      formhash: formhash,
      updatedAt: DateTime(2026),
      source: 'test',
    );

void main() {
  test(
    'guest confirmation is safe and a login permanently expires browsing',
    () {
      final sessions = YamiboSessionStore();
      var expirations = 0;
      final owner = ForumWebViewSessionOwner(
        sessions: sessions,
        onExpired: () => expirations++,
      );
      addTearDown(owner.dispose);
      sessions.saveExtracted(_snapshot('0'));
      sessions.saveExtracted(_snapshot('0', formhash: 'renewed'));
      expect(owner.isCurrent, isTrue);
      expect(expirations, 0);
      sessions.saveExtracted(_snapshot('101'));
      expect(owner.isCurrent, isFalse);
      expect(expirations, 1);
      sessions.clear();
      expect(owner.isCurrent, isFalse);
      expect(expirations, 1);
    },
  );

  test('switching away and back cannot revive the original browser', () {
    final sessions = YamiboSessionStore()..saveExtracted(_snapshot('101'));
    var expirations = 0;
    final owner = ForumWebViewSessionOwner(
      sessions: sessions,
      onExpired: () => expirations++,
    );
    addTearDown(owner.dispose);
    sessions.saveExtracted(_snapshot('101', formhash: 'renewed'));
    expect(owner.isCurrent, isTrue);
    sessions.saveExtracted(_snapshot('102'));
    sessions.saveExtracted(_snapshot('101'));
    expect(owner.isCurrent, isFalse);
    expect(expirations, 1);
  });

  test('disposed browser no longer observes identity transitions', () {
    final sessions = YamiboSessionStore();
    var expirations = 0;
    final owner = ForumWebViewSessionOwner(
      sessions: sessions,
      onExpired: () => expirations++,
    );
    owner.dispose();
    sessions.saveExtracted(_snapshot('101'));
    expect(owner.isCurrent, isFalse);
    expect(expirations, 0);
  });
}
