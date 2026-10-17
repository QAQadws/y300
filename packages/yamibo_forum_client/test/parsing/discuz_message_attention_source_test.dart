import 'package:test/test.dart';

import 'package:yamibo_forum_client/src/parsing/discuz_message_attention_source.dart';

void main() {
  final site = Uri.parse('https://forum.example.test');

  bool accepts(String path) => acceptsDiscuzMessageAttentionHtmlSource(
    site.resolve(path),
    siteOrigin: site,
  );

  group('public navigation is not limited to content detail routes', () {
    for (final path in <String>[
      '/',
      '/index.php?mobile=2',
      '/forum.php?mod=forumdisplay&fid=6',
      '/forum.php?mod=viewthread&tid=7&page=2',
      '/forum.php?mod=guide&view=newthread',
      '/forum.php?mod=announcement',
      '/forum.php?mod=tag&id=3',
      '/forum.php?mod=misc&action=nav',
      '/forum.php?mod=group&fid=6',
      '/forum.php?mod=group&fid=6&action=memberlist',
      '/home.php',
      '/home.php?mod=space&do=profile&uid=8',
      '/home.php?mod=space&do=thread&uid=8',
      '/home.php?mod=space&do=blog&uid=8',
      '/home.php?mod=space&do=album&uid=8',
      '/home.php?mod=space&do=friend&uid=8',
      '/home.php?mod=space&do=home&uid=8',
      '/home.php?mod=space&do=doing&uid=8',
      '/home.php?mod=space&do=share&uid=8',
      '/home.php?mod=space&do=wall&uid=8',
      '/home.php?mod=space&do=favorite&uid=8',
      '/search.php?mod=forum&searchid=9&searchsubmit=yes&page=2',
      '/search.php?mod=curforum&srhfid=6&searchid=9&searchsubmit=yes',
      '/search.php?mod=user&srchtxt=sample',
      '/search.php?mod=blog&searchid=9',
      '/misc.php?mod=tag&id=3&page=2',
      '/misc.php?mod=faq',
      '/misc.php?mod=faq&action=faq&id=3',
      '/misc.php?mod=faq&action=search&keyword=sample',
      '/misc.php?mod=stat&op=trend',
      '/misc.php?mod=ranklist&type=member',
      '/portal.php',
      '/portal.php?mod=list&catid=3',
      '/portal.php?mod=view&aid=4',
      '/portal.php?mod=comment&id=4&idtype=aid',
      '/portal.php?mod=topic&topicid=5',
      '/group.php',
      '/group.php?mod=my&view=groupthread',
      '/group.php?mod=attentiongroup',
      '/thread-7-2-1.html?mobile=2',
      '/forum-6-2.html',
      '/group-6-2.html',
      '/article-4-2.html',
      '/topic-sample.html',
      '/blog-8-9.html',
      '/space-uid-8.html?do=profile',
      '/space-username-sample.html?do=blog&id=9',
    ]) {
      test('accepts a known public page: $path', () {
        expect(accepts(path), isTrue);
      });
    }
  });

  group('existing form preparation GETs', () {
    for (final path in <String>[
      '/forum.php?mod=post&action=newthread&fid=6',
      '/forum.php?mod=post&action=reply&tid=7',
      '/forum.php?mod=post&action=edit&tid=7&pid=8&cedit=yes',
      '/home.php?mod=spacecp&ac=blog',
      '/home.php?mod=spacecp&ac=blog&blogid=9&op=edit',
      '/home.php?mod=spacecp&ac=friend&op=add&uid=8',
      '/home.php?mod=spacecp&ac=comment&op=edit&cid=9',
    ]) {
      test('accepts preparation without command controls: $path', () {
        expect(accepts(path), isTrue);
      });
    }

    for (final path in <String>[
      '/forum.php?mod=post&action=reply&tid=7&replysubmit=yes',
      '/forum.php?mod=post&action=edit&tid=7&editsubmit=yes',
      '/forum.php?mod=post&action=newthread&fid=6&formhash=opaque',
      '/forum.php?mod=post&action=delete&pid=8',
      '/home.php?mod=spacecp&ac=blog&op=delete&blogid=9',
      '/home.php?mod=spacecp&ac=blog&blogsubmit=yes',
      '/home.php?mod=spacecp&ac=friend&op=add&uid=8&add2submit=yes',
      '/home.php?mod=spacecp&ac=friend&op=addconfirm&key=opaque',
      '/home.php?mod=spacecp&ac=friend&op=ignore&key=opaque',
      '/home.php?mod=spacecp&ac=favorite&type=thread&id=7&formhash=opaque',
      '/group.php?mod=attentiongroup&attentionsubmit=yes',
    ]) {
      test('rejects a command or unverified operation: $path', () {
        expect(accepts(path), isFalse);
      });
    }
  });

  group(
    'navigation cannot calibrate pre-consumption or unverified responses',
    () {
      for (final path in <String>[
        '/home.php?mod=space&do=pm',
        '/home.php?mod=space&do=pm&subop=view&touid=8',
        '/home.php?mod=space&do=notice&view=mypost',
        '/home.php?mod=follow',
        '/home.php?mod=follow&do=follower',
        '/home.php?mod=space&do=follow&uid=42',
        '/home.php?mod=space&uid=42',
        '/home.php?mod=space&do=index&uid=8&additional=removevlog',
        '/home.php?mod=spacecp&ac=pm&op=checknewpm',
        '/member.php?mod=logging&action=login',
        '/member.php?mod=logging&action=logout',
        '/plugin.php?id=unknown:page',
        '/forum.php?mod=group&action=join&fid=6',
        '/portal.php?mod=portalcp&ac=article',
        '/misc.php?mod=patch&action=checkpatch',
        '/misc.php?mod=faq&action=plugin&id=unknown',
        '/misc.php?mod=stat&op=modworks&exportexcel=1',
        '/misc.php?mod=tag&type=countitem&id=3',
        '/forum.php?mod=forumdisplay&fid=6&inajax=1',
        '/forum.php?mod=post&action=reply&tid=7&infloat=yes',
        '/search.php?mod=forum&searchid=9&ajax=1',
        '/portal.php?mod=list&action=delete',
        '/forum.php?mod=forumdisplay&mod=forumdisplay',
        '/misc.php?mod=tag&id=3&id=4',
        '/forum.php?mod=viewthread&tid=7#message',
        '/api/mobile/index.php?module=forumindex&version=1',
        '/unknown.php',
        '/space-uid-8.html',
        '/space-username-sample.html',
        '/space-uid-8.html?do=notice',
        '/space-uid-8.html?do=profile&additional=removevlog',
        '/thread-7-2-1.html?mod=post&action=reply',
        '/thread-7-2-1.html?tid=7',
        '/forum-6-2.html?page=2',
        '/blog-8-9.html?do=notice',
        '/topic-sample%26mod%3Dportalcp.html',
        '/space-username-sample%26do%3Dpm.html?do=profile',
        '/unknown-page.html',
      ]) {
        test('rejects source: $path', () {
          expect(accepts(path), isFalse);
        });
      }
    },
  );

  test('origin restrictions apply to every supported route', () {
    for (final uri in <String>[
      'https://other.example.test/search.php?mod=forum',
      'http://forum.example.test/misc.php?mod=tag&id=3',
      'https://forum.example.test:8443/portal.php?mod=view&aid=4',
      'https://viewer@forum.example.test/group.php',
    ]) {
      expect(
        acceptsDiscuzMessageAttentionHtmlSource(
          Uri.parse(uri),
          siteOrigin: site,
        ),
        isFalse,
      );
    }
  });
}
