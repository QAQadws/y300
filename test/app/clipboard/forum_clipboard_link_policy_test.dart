import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/clipboard/forum_clipboard_link_policy.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';

void main() {
  const policy = ForumClipboardLinkPolicy();
  const origin = 'https://bbs.yamibo.com';
  const thread = '$origin/thread-123-2-1.html';
  const forum = '$origin/forum-42-3.html';
  const blog = '$origin/home.php?mod=space&uid=101&do=blog&id=11';

  group('ForumClipboardLinkPolicy', () {
    test(
      'only locally proven thread, floor, forum and blog targets qualify',
      () {
        for (final entry in {
          thread: ForumClipboardLinkKind.thread,
          '$origin/forum.php?mod=viewthread&tid=123&page=2':
              ForumClipboardLinkKind.thread,
          '$thread#pid456': ForumClipboardLinkKind.threadPost,
          '$origin/forum.php?mod=redirect&goto=findpost&ptid=123&pid=456':
              ForumClipboardLinkKind.threadPost,
          forum: ForumClipboardLinkKind.forum,
          '$origin/forum.php?mod=forumdisplay&fid=42&page=3':
              ForumClipboardLinkKind.forum,
          blog: ForumClipboardLinkKind.blog,
          '$blog&page=2': ForumClipboardLinkKind.blog,
          '$blog&cid=42#comment_42': ForumClipboardLinkKind.blog,
          '$blog&goto=last': ForumClipboardLinkKind.blog,
        }.entries) {
          final candidate = policy.resolve('分享：“${entry.key}”。');
          expect(candidate?.url, entry.key, reason: entry.key);
          expect(candidate?.kind, entry.value, reason: entry.key);
          expect(candidate?.fingerprint, matches(RegExp(r'^[a-f0-9]{64}$')));
        }
      },
    );

    test(
      'external and action links are filtered before the unique-target gate',
      () {
        final candidate = policy.resolve(
          'https://example.com/ $thread '
          '$origin/member.php?mod=logging&action=logout&formhash=proof '
          '$origin/forum.php?mod=post&action=delete&tid=123',
        );
        expect(candidate?.url, thread);
        expect(candidate?.kind, ForumClipboardLinkKind.thread);
        for (final input in [
          'https://example.com/',
          '$origin/member.php?mod=logging&action=login',
          '$thread?action=delete',
          '$thread?formhash=proof',
          '$thread?replysubmit=1',
          '$origin/home.php?mod=spacecp&ac=friend&op=ignore&uid=101',
          '$origin/',
          '$origin/search.php?mod=forum',
          '$origin/misc.php?mod=tag&id=28',
          '$origin/home.php?mod=space&do=friend',
          '$origin/home.php?mod=space&do=thread&uid=101',
          '$origin/unknown.php?tid=123',
        ]) {
          expect(policy.resolve(input), isNull, reason: input);
        }
      },
    );

    test(
      'repeat occurrences and proven native URL aliases share one target',
      () {
        for (final urls in [
          [thread, thread],
          [thread, '$origin/forum.php?mod=viewthread&tid=123&page=2'],
          [
            '$origin/thread-123-1-1.html',
            '$origin/forum.php?mod=viewthread&tid=123',
          ],
          [
            '$thread#pid456',
            '$origin/forum.php?mod=viewthread&tid=123&page=2#pid456',
          ],
          [forum, '$origin/forum.php?mod=forumdisplay&fid=42&page=3'],
          [
            blog,
            '$origin/home.php?do=blog&id=11&uid=101&mod=space&page=1&mobile=2',
          ],
          [blog, blog.replaceFirst('https:', 'http:')],
          ['$blog&cid=42', '$blog#comment_42_li'],
          ['$blog#comment', '$blog#quickcommentform_11'],
        ]) {
          final first = policy.resolve(urls.first);
          final second = policy.resolve(urls.last);
          final combined = policy.resolve(urls.join(' '));
          expect(first, isNotNull, reason: urls.toString());
          expect(
            second?.fingerprint,
            first!.fingerprint,
            reason: urls.toString(),
          );
          expect(combined?.url, urls.first, reason: urls.toString());
          expect(
            combined?.fingerprint,
            first.fingerprint,
            reason: urls.toString(),
          );
        }
      },
    );

    test('different thread, page, floor or forum identity stays ambiguous', () {
      for (final input in [
        '$thread $origin/thread-124-2-1.html',
        '$thread $origin/thread-123-3-1.html',
        '$thread $thread#pid456',
        '$thread#pid456 $thread#pid457',
        '$thread#pid456 $origin/thread-123-3-1.html#pid456',
        '$forum $origin/forum-42-4.html',
        '$forum $origin/forum-43-3.html',
        '$thread $forum',
      ]) {
        expect(policy.resolve(input), isNull, reason: input);
      }
    });

    test('blog identity retains owner and comment navigation intent', () {
      for (final input in [
        '$blog ${blog.replaceFirst('uid=101', 'uid=102')}',
        '$blog ${blog.replaceFirst('id=11', 'id=12')}',
        '$blog $blog&page=2',
        '$blog $blog#comment',
        '$blog&cid=42 $blog&cid=43',
        '$blog&page=2 $blog&page=3',
        '$blog $blog&goto=last',
        '$blog $thread',
        '$blog $forum',
      ]) {
        expect(policy.resolve(input), isNull, reason: input);
      }
      final candidate = policy.resolve('https://example.test/ 分享：$blog。');
      expect(candidate?.kind, ForumClipboardLinkKind.blog);
      expect(candidate?.url, blog);
    });

    test('blog commands, feeds and unproven article links are ignored', () {
      for (final input in [
        '$origin/home.php?mod=space&do=blog&view=all',
        '$origin/home.php?mod=space&do=blog&view=me&uid=101',
        '$origin/home.php?mod=spacecp&ac=blog&op=edit&blogid=11',
        '$origin/home.php?mod=spacecp&ac=comment&op=delete&cid=42',
        '$origin/home.php?mod=space&do=blog&id=11',
        '$blog&uid=102',
        '$blog&page=0',
        blog.replaceFirst('uid=101', 'uid=0'),
        blog.replaceFirst('id=11', 'id=0'),
        '$blog&action=delete',
        '$blog&formhash=proof',
        '$blog&replysubmit=1',
        '$blog&unknown=1',
        '$blog&cid=42#comment_43',
        '$blog&cid=42&goto=last',
        '$blog&page=2&cid=42',
        '$blog&page=2#comment_42_li',
        '$blog&page=2&goto=last',
        '$blog#unknown',
        '$blog&goto=last#unknown',
        blog.replaceFirst('bbs.yamibo.com', 'bbs.yamibo.com.example.test'),
        blog.replaceFirst('bbs.yamibo.com', 'someone@bbs.yamibo.com'),
        blog.replaceFirst('bbs.yamibo.com', 'bbs.yamibo.com:8443'),
      ]) {
        expect(policy.resolve(input), isNull, reason: input);
      }
    });

    test('managed browsing preserves original parameters and exact identity', () {
      const managed =
          '$origin/forum.php?mod=viewthread&tid=123&authorid=101&unknown=1#pid456';
      final candidate = policy.resolve('$managed $managed');
      expect(candidate?.url, managed);
      expect(candidate?.kind, ForumClipboardLinkKind.threadPost);
      for (final input in [
        '$managed $origin/forum.php?mod=viewthread&tid=123&authorid=102&unknown=1#pid456',
        '$managed $origin/forum.php?unknown=1&mod=viewthread&tid=123&authorid=101#pid456',
        '$managed $origin/forum.php?mod=viewthread&tid=123#pid456',
      ]) {
        expect(policy.resolve(input), isNull, reason: input);
      }
      for (final entry in {
        '$thread?unknown=1': ForumClipboardLinkKind.thread,
        '$forum?filter=typeid&typeid=2': ForumClipboardLinkKind.forum,
      }.entries) {
        expect(policy.resolve(entry.key)?.url, entry.key);
        expect(policy.resolve(entry.key)?.kind, entry.value);
      }
      const resolver = YamiboForumLinkResolver();
      final destination = resolver.resolveBrowsable(managed);
      final identity = resolver.resolveBrowsingIdentity(managed);
      expect(destination?.kind, YamiboForumLinkKind.managedWebView);
      expect(destination?.uri.toString(), managed);
      expect(identity?.kind, YamiboForumLinkKind.threadPost);
      expect(identity?.tid, '123');
      expect(identity?.pid, '456');
      expect(identity?.uri.queryParameters.containsKey('unknown'), isFalse);
    });

    test('partial, fake or unsupported URLs cannot become recommendations', () {
      for (final input in [
        'https://bbs.yamibo.com.example.com/thread-123-2-1.html',
        'https://somebody@bbs.yamibo.com/thread-123-2-1.html',
        'https://bbs.yamibo.com:8443/thread-123-2-1.html',
        '$origin/thread-123-2-',
        '$origin/thread-123-\n2-1.html',
        '$origin/forum.php?mod=viewthread&tid=',
        '$origin/forum.php?mod=viewthread&tid=123&tid=124',
        '$origin/forum.php?mod=viewthread&tid=123&page=0',
        '/thread-123-2-1.html',
        'javascript:$thread',
        '$thread#pid',
        '$thread?unknown=%',
        '没有网址',
        '',
      ]) {
        expect(policy.resolve(input), isNull, reason: input);
      }
    });

    test('scan limits apply before filtering or deduplication', () {
      expect(policy.resolve('${'a' * (64 * 1024)} $thread'), isNull);
      expect(policy.resolve('$thread?unknown=${'a' * (8 * 1024)}'), isNull);
      expect(policy.resolve(List.filled(11, thread).join(' ')), isNull);
      expect(
        policy.resolve(
          '${List.filled(10, 'https://example.com/').join(' ')} $thread',
        ),
        isNull,
      );
    });
  });
}
