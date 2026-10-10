import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/navigation/forum_selected_link_policy.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';

void main() {
  const policy = ForumSelectedLinkPolicy();
  const resolver = YamiboForumLinkResolver();
  const origin = 'https://bbs.yamibo.com';
  const thread = '$origin/thread-123-2-1.html';

  group('ForumSelectedLinkPolicy', () {
    test('known browsing URLs retain the exact selected URL text', () {
      for (final url in [
        thread,
        '$thread#pid456',
        '$origin/forum.php?mod=viewthread&tid=123&page=2#pid456',
        '$origin/forum.php?mod=redirect&goto=findpost&ptid=123&pid=456',
        '$origin/forum.php?mod=forumdisplay&fid=42&page=3',
        '$origin/forum-42-3.html',
        '$origin/',
        '$origin/index.php?mobile=2',
        '$origin/forum.php?mod=index',
        '$origin/search.php?mod=forum&srhfid=42',
        '$origin/misc.php?mod=tag&id=28',
        '$origin/home.php?mod=space&do=thread&uid=101&type=reply',
        '$origin/home.php?mod=space&do=friend',
        'HTTP://BBS.YAMIBO.COM/thread-123-2-1.html',
        'https://bbs.yamibo.com:443/thread-123-2-1.html',
      ]) {
        expect(policy.resolve(url), url, reason: url);
        expect(policy.resolve('分享：$url。'), url, reason: url);
      }
    });

    test('unknown view filters keep managed browsing and all URI fields', () {
      for (final url in [
        '$thread?unknown=original%2Fvalue&filter=typeid&typeid=2',
        '$origin/forum.php?mod=viewthread&tid=123&authorid=101',
        '$origin/forum.php?mod=viewthread&tid=123&ordertype=1',
        '$origin/forum.php?mod=viewthread&tid=123&unknown=1#pid456',
        '$origin/forum.php?mod=redirect&goto=findpost&ptid=123&pid=456&unknown=1',
        '$origin/forum.php?mod=forumdisplay&fid=42&filter=author',
        '$origin/forum-42-3.html?filter=typeid&typeid=2',
        '$origin/search.php?mod=forum&searchid=42&page=2',
        '$origin/index.php?gid=4',
        '$origin/home.php?mod=space&do=thread&uid=101&searchkey=query',
      ]) {
        expect(policy.resolve('请看 $url'), url, reason: url);
        final destination = resolver.resolveBrowsable(url);
        expect(
          destination?.kind,
          YamiboForumLinkKind.managedWebView,
          reason: url,
        );
        expect(destination?.uri.toString(), url, reason: url);
      }
    });

    test('only one occurrence is eligible before site filtering or dedup', () {
      for (final selected in [
        '$thread $thread',
        '$thread，$thread',
        '$thread\n$origin/forum-42-3.html',
        'https://example.com/ $thread',
        '$thread https://example.com/',
        'https://example.com/ https://another.example.org/',
      ]) {
        expect(policy.resolve(selected), isNull, reason: selected);
      }
    });

    test('limited input and overlong URLs fail closed', () {
      expect(policy.resolve('${'a' * (64 * 1024)} $thread'), isNull);
      expect(policy.resolve('$thread?unknown=${'a' * (8 * 1024)}'), isNull);
      expect(policy.resolve(List.filled(11, thread).join(' ')), isNull);
    });

    test(
      'external, credentialed and ambiguous origins are not forum targets',
      () {
        for (final url in [
          'https://example.com/thread-123-2-1.html',
          'https://bbs.yamibo.com.example.com/thread-123-2-1.html',
          'https://bbs-yamibo.com/thread-123-2-1.html',
          'https://bbs.yamibo.com@evil.example.com/thread-123-2-1.html',
          'https://someone@bbs.yamibo.com/thread-123-2-1.html',
          'https://bbs.yamibo.com:8443/thread-123-2-1.html',
          'http://bbs.yamibo.com:443/thread-123-2-1.html',
          'ftp://bbs.yamibo.com/thread-123-2-1.html',
          'javascript:$thread',
          'data:$thread',
        ]) {
          expect(policy.resolve(url), isNull, reason: url);
        }
      },
    );

    test('actions and unknown managed targets never gain a menu action', () {
      for (final url in [
        '$origin/member.php?mod=logging&action=login',
        '$origin/member.php?mod=logging&action=logout&formhash=proof',
        '$origin/forum.php?mod=post&action=edit&tid=123&pid=456',
        '$origin/forum.php?mod=viewthread&tid=123&action=printable',
        '$thread?action=delete',
        '$thread?ACTION=delete',
        '$thread?ac=post',
        '$thread?op=delete',
        '$thread?formhash=proof',
        '$thread?replysubmit=1',
        '$thread?submit=1',
        '$thread?mod=post',
        '$thread?goto=lastpost',
        '$origin/home.php?mod=spacecp&ac=friend&op=ignore&uid=101',
        '$origin/home.php?mod=space&do=profile&uid=101',
        '$origin/home.php?mod=space&do=notice',
        '$origin/misc.php?mod=tag&id=28&type=blog',
        '$origin/unknown.php?tid=123',
        '$origin/api/mobile/index.php?module=viewthread&tid=123',
      ]) {
        expect(policy.resolve(url), isNull, reason: url);
        expect(resolver.resolveBrowsable(url), isNull, reason: url);
      }
    });

    test('ambiguous or incomplete resource selectors remain ineligible', () {
      for (final url in [
        '$origin/forum.php?mod=viewthread&tid=',
        '$origin/forum.php?mod=viewthread&tid=0',
        '$origin/forum.php?mod=viewthread&tid=123&tid=456',
        '$thread?filter=one&filter=two',
        '$origin/forum.php?mod=viewthread&tid=123&page=0',
        '$origin/forum.php?mod=redirect&goto=findpost&ptid=123&pid=',
        '$origin/forum.php?mod=redirect&goto=findpost&ptid=123&pid=bad',
        '$origin/forum.php?mod=forumdisplay&fid=',
        '$origin/forum.php?mod=forumdisplay&fid=0',
        '$origin/forum-42-0.html',
        '$origin/thread-123-2-',
        '$origin/thread-123-2-1.htm',
        '$thread#pid',
        '$thread?unknown=%',
        '$origin/thread-123-\n2-1.html',
        '/thread-123-2-1.html',
        'thread-123-2-1.html',
        'https://',
        'https://bbs.yamibo',
        '没有网址',
        '',
      ]) {
        expect(policy.resolve(url), isNull, reason: url);
      }
    });

    test(
      'encoded query and explicit floor identity remain source-preserving',
      () {
        const url =
            '$origin/forum.php?mod=viewthread&tid=123&page=2'
            '&highlight=%E7%AB%A0%E8%8A%82%28%E4%B8%80%29#pid456';
        expect(policy.resolve('“$url”'), url);
        final destination = resolver.resolveBrowsable(url);
        expect(destination?.kind, YamiboForumLinkKind.threadPost);
        expect(destination?.tid, '123');
        expect(destination?.pid, '456');
        expect(destination?.page, 2);
        expect(destination?.uri.toString(), url);
      },
    );

    test(
      'selection classification does not change ordinary resolver fallback',
      () {
        const url = '$thread?action=printable';
        expect(resolver.resolveBrowsable(url), isNull);
        expect(resolver.resolve(url)?.kind, YamiboForumLinkKind.managedWebView);
        expect(resolver.resolve(url)?.uri.toString(), url);
      },
    );
  });

  group('ForumSelectedLinkSource', () {
    test('HTML evidence preserves preformatted hard line continuations', () {
      for (final html in [
        '<pre>$thread\n?authorid=101</pre>',
        '<code>$thread\n#pid456</code>',
        '<div style="white-space:pre-wrap">$thread\n?page=2</div>',
        '<p>$thread<br>?authorid=101</p>',
      ]) {
        expect(
          ForumSelectedLinkSource.fromHtml(html).confirms(thread),
          isFalse,
          reason: html,
        );
      }
    });

    test('HTML evidence joins inline text but separates adjacent blocks', () {
      final source = ForumSelectedLinkSource.fromHtml(
        '<p><b>https://bbs.yamibo.com/</b>'
        '<span>thread-123-2-1.html</span></p><p>description</p>'
        '<p>https://example.test/other</p>',
      );
      expect(source.confirms(thread), isTrue);
      expect(source.confirms('${thread}description'), isFalse);
    });

    test('complete query and fragment are proved without URL rewriting', () {
      const url = '$thread?highlight=%E7%AB%A0%E8%8A%82&page=2#pid456';
      final source = ForumSelectedLinkSource.fromText('分享：$url。');
      expect(source.confirms(url), isTrue);
      expect(source.confirms(thread), isFalse);
      expect(source.confirms('$thread?highlight=%E7%AB%A0%E8%8A%82'), isFalse);
      expect(
        source.confirms('$thread?highlight=%E7%AB%A0%E8%8A%82&page='),
        isFalse,
      );
      expect(
        source.confirms('$thread?highlight=%E7%AB%A0%E8%8A%82&page=2'),
        isFalse,
      );
      expect(
        source.confirms('$thread?highlight=%E7%AB%A0%E8%8A%82&page=2#pid45'),
        isFalse,
      );
    });

    test('a base URL elsewhere cannot prove a longer URL prefix selection', () {
      const longer = '$thread?authorid=101#pid456';
      final source = ForumSelectedLinkSource.fromText('$thread\n$longer');
      expect(source.confirms(thread), isFalse);
      expect(source.confirms(longer), isTrue);
      expect(source.confirms('$thread?authorid=101'), isFalse);
    });

    test('full page identity must match the source rather than be guessed', () {
      const longer = '$origin/forum.php?mod=viewthread&tid=123&page=23';
      final source = ForumSelectedLinkSource.fromText(longer);
      expect(source.confirms(longer), isTrue);
      expect(
        source.confirms('$origin/forum.php?mod=viewthread&tid=123&page=2'),
        isFalse,
      );
      expect(
        source.confirms('$origin/forum.php?mod=viewthread&tid=123'),
        isFalse,
      );
    });

    test(
      'source input may be a large body but URL limits still fail closed',
      () {
        final source = ForumSelectedLinkSource.fromText(
          '${'正文' * (64 * 1024)} $thread',
        );
        expect(source.confirms(thread), isTrue);
        final limitedSource = ForumSelectedLinkSource.fromText(
          '$thread https://example.com/?value=${'a' * (8 * 1024)}',
        );
        expect(limitedSource.confirms(thread), isFalse);
      },
    );

    test('unknown, empty and source-split URLs never prove completeness', () {
      for (final text in ['', '只有文字', '$origin/thread-123-\n2-1.html']) {
        expect(
          ForumSelectedLinkSource.fromText(text).confirms(thread),
          isFalse,
          reason: text,
        );
      }
      expect(
        ForumSelectedLinkSource.fromText(thread).confirms('$thread#pid456'),
        isFalse,
      );
    });
  });
}
