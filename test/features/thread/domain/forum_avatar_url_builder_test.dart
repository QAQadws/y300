import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/services/forum_avatar_url_builder.dart';

void main() {
  const builder = DefaultForumAvatarUrlBuilder();

  test('pads user id into the Discuz middle avatar path', () {
    expect(
      builder.buildMiddleAvatar('422014').toString(),
      'https://bbs.yamibo.com/uc_server/data/avatar/000/42/20/14_avatar_middle.jpg',
    );
    expect(
      builder.buildMiddleAvatar('8').toString(),
      'https://bbs.yamibo.com/uc_server/data/avatar/000/00/00/08_avatar_middle.jpg',
    );
  });

  test('rejects empty, non-numeric and oversized ids', () {
    expect(builder.buildMiddleAvatar(''), isNull);
    expect(builder.buildMiddleAvatar('anonymous'), isNull);
    expect(builder.buildMiddleAvatar('1234567890'), isNull);
  });
}
