import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_ucenter_avatar_resolver.dart';

void main() {
  DiscuzUCenterAvatarResolver resolver(String avatar, {String uid = '10'}) =>
      DiscuzUCenterAvatarResolver(
        siteOrigin: Uri.parse('https://forum.example.test/'),
        currentUserId: uid,
        currentUserAvatar: avatar,
      );

  test('static avatar derives the advertised root and middle size', () {
    final source = resolver(
      'https://cdn.example.test/avatars/000/00/00/10_avatar_small.jpg?ts=99',
    );
    expect(
      source.resolve('123456789'),
      'https://cdn.example.test/avatars/123/45/67/89_avatar_middle.jpg',
    );
    expect(
      source.resolve('10'),
      'https://cdn.example.test/avatars/000/00/00/10_avatar_middle.jpg?ts=99',
    );
  });

  test('relative and protocol-relative paths preserve real-avatar layout', () {
    for (final prefix in ['/avatars', '//forum.example.test/avatars']) {
      expect(
        resolver('$prefix/000/00/00/10_real_avatar_big.jpg').resolve('20'),
        'https://forum.example.test/avatars/000/00/00/20_real_avatar_middle.jpg',
      );
    }
    expect(
      resolver('avatars/000/00/00/10_avatar_small.jpg').resolve('20'),
      'https://forum.example.test/avatars/000/00/00/20_avatar_middle.jpg',
    );
  });

  test(
    'dynamic endpoint retains type but not another user timestamp or random',
    () {
      final source = resolver(
        '/uc/avatar.php?uid=10&size=small&type=real&ts=1&random=1',
      );
      expect(
        source.resolve('20'),
        'https://forum.example.test/uc/avatar.php?uid=20&size=middle&type=real',
      );
      expect(
        source.resolve('10'),
        'https://forum.example.test/uc/avatar.php?uid=10&size=middle&type=real&ts=1',
      );
    },
  );

  test('a known default applies only to the current user', () {
    final source = resolver('/uc/data/avatar/noavatar.svg?random=888');
    expect(
      source.resolve('10'),
      'https://forum.example.test/uc/data/avatar/noavatar.svg',
    );
    expect(
      source.resolve('20'),
      'https://forum.example.test/uc/data/avatar/000/00/00/20_avatar_middle.jpg',
    );
  });

  for (final avatar in [
    '',
    '/uc/avatar.php?uid=11&size=small',
    '/uc/avatar.php?uid=10&uid=11',
    '/uc/avatar.php?uid=10&token=secret',
    '/uc/avatar.php?uid=10&type=plugin',
    '/uc/avatar.php?uid=10&size=%FF',
    '/uc/data/avatar/000/00/00/11_avatar_small.jpg',
    '/uc/data/avatar/000/00/00/10_avatar_small.jpg?signature=private',
    '/plugin/avatar/10.png',
    '/uc/data/avatar/custom.svg',
    'file:///uc/data/avatar/noavatar.svg',
    'https://user:secret@forum.example.test/uc/data/avatar/noavatar.svg',
  ]) {
    test('unknown or unproven avatar is unavailable: $avatar', () {
      expect(resolver(avatar).resolve('20'), isNull);
    });
  }

  for (final id in ['', '0', '-2', '2&uid=3', 'abc', '1000000000']) {
    test('invalid target and current identities are rejected: $id', () {
      expect(resolver('/uc/data/avatar/noavatar.svg').resolve(id), isNull);
      expect(
        resolver('/uc/data/avatar/noavatar.svg', uid: id).resolve('20'),
        isNull,
      );
    });
  }
}
