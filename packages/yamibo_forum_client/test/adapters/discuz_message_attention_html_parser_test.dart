import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:yamibo_forum_client/src/parsing/discuz_html_document.dart';

import '../fixtures/message_attention_html_fixtures.dart';

void main() {
  final origin = Uri.parse('https://forum.example.test');
  final pageUri = Uri.parse(
    'https://forum.example.test/forum.php?mod=forumdisplay&fid=6&mobile=2',
  );
  final parser = DiscuzMessageAttentionHtmlParser(siteOrigin: origin);

  ForumMessageAttentionObservation? parse(
    String html, {
    Uri? sourceUri,
    String expectedUserId = '42',
  }) => parser.parse(
    html,
    sourceUri: sourceUri ?? pageUri,
    expectedUserId: expectedUserId,
  );

  group('mobile public navigation', () {
    test(
      'shared dot establishes aggregate evidence without invented items',
      () {
        final observation = parse(mobileAttentionHtml(messageDot: true))!;
        expect(observation.viewerUserId, '42');
        expect(observation.source, ForumMessageAttentionSource.mobileHtml);
        expect(observation.combinedHint, ForumMessageAttentionState.present);
        expect(observation.combined, ForumMessageAttentionState.present);
        expect(observation.privateMessages, ForumMessageAttentionState.unknown);
        expect(observation.notifications, ForumMessageAttentionState.unknown);
        expect(observation.notificationCount, isNull);
      },
    );

    test('complete supported message entry without a dot is inactive', () {
      final observation = parse(mobileAttentionHtml())!;
      expect(observation.combinedHint, ForumMessageAttentionState.absent);
      expect(observation.combined, ForumMessageAttentionState.absent);
      expect(observation.privateMessages, ForumMessageAttentionState.unknown);
      expect(observation.notifications, ForumMessageAttentionState.unknown);
      expect(observation.notificationCount, isNull);
    });

    test('absence of a profile dot does not negate the message dot', () {
      expect(
        parse(mobileAttentionHtml(messageDot: true))?.combined,
        ForumMessageAttentionState.present,
      );
    });

    test('conflicting shared icons do not supply inactive evidence', () {
      expect(parse(mobileAttentionHtml(profileDot: true)), isNull);
    });

    test('the companion profile entry must identify the response viewer', () {
      expect(
        parse(
          mobileAttentionHtml(
            profileHref:
                'home.php?mod=space&amp;uid=99&amp;do=profile&amp;mycenter=1',
          ),
        ),
        isNull,
      );
    });

    test('two links alone do not establish the supported footer shape', () {
      expect(
        parse(
          mobileAttentionHtml().replaceFirst(
            RegExp(r'<a href="forum\.php" class="flex mon">[\s\S]*?</a>'),
            '',
          ),
        ),
        isNull,
      );
    });

    test('nofooter pages do not imply that attention is inactive', () {
      expect(parse(mobileAttentionHtml(includeFooter: false)), isNull);
    });

    test('default touch profile-only dot proves a combined positive', () {
      final observation = parse(
        mobileAttentionHtml(defaultTouchProfileOnly: true, profileDot: true),
      )!;
      expect(observation.source, ForumMessageAttentionSource.mobileHtml);
      expect(observation.combinedHint, ForumMessageAttentionState.present);
      expect(observation.privateMessages, ForumMessageAttentionState.unknown);
      expect(observation.notifications, ForumMessageAttentionState.unknown);
      expect(observation.notificationCount, isNull);
    });

    test('default touch profile-only absence is unknown', () {
      expect(parse(mobileAttentionHtml(defaultTouchProfileOnly: true)), isNull);
    });

    test('profile-only evidence still requires the authenticated own link', () {
      expect(
        parse(
          mobileAttentionHtml(
            defaultTouchProfileOnly: true,
            profileDot: true,
            profileHref: 'home.php?mod=space&amp;uid=99&amp;do=profile',
          ),
        ),
        isNull,
      );
    });

    test('nofooter cannot borrow a profile-only dot from body content', () {
      expect(
        parse(
          mobileAttentionHtml(
            includeFooter: false,
            content:
                '<div id="ct">${mobileAttentionFooter(defaultTouchProfileOnly: true, profileDot: true)}</div>',
          ),
        ),
        isNull,
      );
    });

    test('content dots and action footers are not navigation evidence', () {
      final observation = parse(
        mobileAttentionHtml(
          content:
              '''
<div id="ct"><i class="ico_msg"></i>${mobileAttentionFooter(messageDot: true)}</div>
<div class="foot_reply"><i class="ico_msg"></i></div>
''',
        ),
      )!;
      expect(observation.combined, ForumMessageAttentionState.absent);
    });

    test('a footer copied inside post content is not public chrome', () {
      expect(
        parse(
          mobileAttentionHtml(
            includeFooter: false,
            content: '<div id="ct">${mobileAttentionFooter()}</div>',
          ),
        ),
        isNull,
      );
    });

    test('checknewpm script inclusion is not an arrival indicator', () {
      expect(
        parse(mobileAttentionHtml())?.combined,
        ForumMessageAttentionState.absent,
      );
    });

    test('links use resolved same-site targets and normalized parameters', () {
      final observation = parse(
        mobileAttentionHtml(
          messageDot: true,
          messageHref:
              'https://forum.example.test/home.php?mobile=2&amp;do=pm&amp;mod=space',
        ),
      );
      expect(observation?.combined, ForumMessageAttentionState.present);
    });

    test('a standard rewritten own-profile link retains viewer proof', () {
      expect(
        parse(
          mobileAttentionHtml(
            messageDot: true,
            profileHref: 'space-uid-42.html',
          ),
        )?.combined,
        ForumMessageAttentionState.present,
      );
      expect(
        parse(
          mobileAttentionHtml(
            messageDot: true,
            profileHref: 'space-uid-99.html',
          ),
        ),
        isNull,
      );
    });

    for (final href in <String>[
      'https://external.example.test/home.php?mod=space&amp;do=pm',
      '//external.example.test/home.php?mod=space&amp;do=pm',
      'javascript:alert(1)',
      'home.php?mod=space&amp;do=pm&amp;do=notice',
      'home.php?mod=space&amp;mod=spacecp&amp;do=pm',
      'home.php?mod=spacecp&amp;ac=pm',
    ]) {
      test('untrusted message target yields no inactive evidence: $href', () {
        expect(parse(mobileAttentionHtml(messageHref: href)), isNull);
      });
    }
  });

  group('desktop scoped indicators', () {
    test(
      'real duplicate PM IDs are parsed in their separate chrome scopes',
      () {
        final observation = parse(
          desktopAttentionHtml(
            privateMessageDot: true,
            notificationDot: true,
            notificationSuffix: '(3)',
          ),
        )!;
        expect(observation.source, ForumMessageAttentionSource.desktopHtml);
        expect(observation.privateMessages, ForumMessageAttentionState.present);
        expect(observation.notifications, ForumMessageAttentionState.present);
        expect(observation.notificationCount, 3);
        expect(observation.combinedHint, ForumMessageAttentionState.unknown);
        expect(observation.combined, ForumMessageAttentionState.present);
      },
    );

    test(
      'full normal-display shell without indicators establishes absence',
      () {
        final observation = parse(desktopAttentionHtml())!;
        expect(observation.privateMessages, ForumMessageAttentionState.absent);
        expect(observation.notifications, ForumMessageAttentionState.absent);
        expect(observation.notificationCount, 0);
        expect(observation.combined, ForumMessageAttentionState.absent);
      },
    );

    test('default Discuz desktop user area is supported', () {
      final observation = parse(
        desktopAttentionHtml(defaultTemplate: true, privateMessageDot: true),
      )!;
      expect(observation.source, ForumMessageAttentionSource.desktopHtml);
      expect(observation.privateMessages, ForumMessageAttentionState.present);
    });

    test(
      'desktop rewrite of the avatar profile link retains identity proof',
      () {
        final source = desktopAttentionHtml(
          privateMessageDot: true,
        ).replaceFirst('home.php?mod=space&amp;uid=42', 'space-uid-42.html');
        expect(parse(source)?.combined, ForumMessageAttentionState.present);
      },
    );

    test(
      'suppressed menu does not turn missing notification class into zero',
      () {
        final observation = parse(desktopAttentionHtml(includeMenu: false))!;
        expect(observation.privateMessages, ForumMessageAttentionState.absent);
        expect(observation.notifications, ForumMessageAttentionState.unknown);
        expect(observation.notificationCount, isNull);
        expect(observation.combined, ForumMessageAttentionState.unknown);
      },
    );

    test('positive notification remains evidence without the hidden menu', () {
      final observation = parse(
        desktopAttentionHtml(
          notificationDot: true,
          notificationSuffix: '(2)',
          includeMenu: false,
        ),
      )!;
      expect(observation.notifications, ForumMessageAttentionState.present);
      expect(observation.notificationCount, 2);
    });

    test(
      'conflicting top and menu PM evidence preserves category uncertainty',
      () {
        final observation = parse(
          desktopAttentionHtml(
            privateMessageDot: true,
            menuPrivateMessageDot: false,
            notificationDot: true,
            notificationSuffix: '(2)',
          ),
        )!;
        expect(observation.privateMessages, ForumMessageAttentionState.unknown);
        expect(observation.notifications, ForumMessageAttentionState.present);
        expect(observation.combined, ForumMessageAttentionState.present);
      },
    );

    test('body content duplicate IDs and generic new classes are ignored', () {
      final observation = parse(
        desktopAttentionHtml(
          content:
              '''
<div id="ct">
  <a id="pm_ntc" class="new" href="home.php?mod=space&amp;do=pm">Post link</a>
  <a id="myprompt" class="new" href="home.php?mod=space&amp;do=notice">Post link(99)</a>
  ${desktopAttentionMenu(privateMessageDot: true)}
  ${desktopAttentionTop(privateMessageDot: true, notificationDot: true)}
</div>
''',
        ),
      )!;
      expect(observation.privateMessages, ForumMessageAttentionState.absent);
      expect(observation.notifications, ForumMessageAttentionState.absent);
      expect(observation.combined, ForumMessageAttentionState.absent);
    });

    test('menu nested in content cannot prove normal display conditions', () {
      final observation = parse(
        desktopAttentionHtml(
          includeMenu: false,
          content: '<div id="ct">${desktopAttentionMenu()}</div>',
        ),
      )!;
      expect(observation.notifications, ForumMessageAttentionState.unknown);
    });

    test(
      'positive class does not manufacture a missing notification count',
      () {
        final observation = parse(desktopAttentionHtml(notificationDot: true))!;
        expect(observation.notifications, ForumMessageAttentionState.present);
        expect(observation.notificationCount, isNull);
      },
    );

    for (final suffix in <String>[
      '(0)',
      '(-2)',
      '(+2)',
      '(2.0)',
      '(0x2a)',
      '(２)',
      '(2) (3)',
      '(9999999999999999999999999999999999999999)',
    ]) {
      test(
        'malformed count stays unknown while class remains positive: $suffix',
        () {
          final observation = parse(
            desktopAttentionHtml(
              notificationDot: true,
              notificationSuffix: suffix,
            ),
          )!;
          expect(observation.notifications, ForumMessageAttentionState.present);
          expect(observation.notificationCount, isNull);
        },
      );
    }
  });

  group('shared full-page decoding', () {
    test('business and attention reads keep one unmodified document', () {
      final source = DiscuzHtmlDocument.fromSource(
        mobileAttentionHtml(
          messageDot: true,
          content: '<div id="ct"><p id="body">Business content.</p></div>',
        ),
      );
      final document = source.document;
      final before = document.outerHtml;
      expect(document.querySelector('#body')?.text, 'Business content.');

      final observation = parser.parseDocument(
        source,
        sourceUri: pageUri,
        expectedUserId: '42',
      );

      expect(observation?.combined, ForumMessageAttentionState.present);
      expect(source.document, same(document));
      expect(document.outerHtml, before);
    });

    test(
      'a business parser repairing an incomplete page cannot prove absence',
      () {
        final source = DiscuzHtmlDocument.fromSource(
          mobileAttentionHtml().replaceFirst('</html>', ''),
        );
        expect(source.document.body, isNotNull);
        expect(
          parser.parseDocument(
            source,
            sourceUri: pageUri,
            expectedUserId: '42',
          ),
          isNull,
        );
      },
    );

    test('navigation evidence does not depend on a business content root', () {
      final source = DiscuzHtmlDocument.fromSource(
        mobileAttentionHtml(content: '<p>No thread-detail rows.</p>'),
      );
      expect(source.document.querySelector('.viewthread'), isNull);
      expect(
        parser
            .parseDocument(source, sourceUri: pageUri, expectedUserId: '42')
            ?.combined,
        ForumMessageAttentionState.absent,
      );
    });
  });

  group('global public shell coverage', () {
    final shells = <String, String>{
      'custom touch': mobileAttentionHtml(messageDot: true),
      'default touch profile-only': mobileAttentionHtml(
        defaultTouchProfileOnly: true,
        profileDot: true,
      ),
      'custom desktop': desktopAttentionHtml(privateMessageDot: true),
      'default desktop': desktopAttentionHtml(
        defaultTemplate: true,
        privateMessageDot: true,
      ),
    };
    final paths = <String>[
      '/search.php?mod=forum&searchid=9&searchsubmit=yes&page=2',
      '/search.php?mod=curforum&srhfid=6&searchid=9&searchsubmit=yes',
      '/misc.php?mod=tag&id=3&page=2',
      '/misc.php?mod=faq',
      '/portal.php?mod=view&aid=4',
      '/portal.php?mod=comment&id=4&idtype=aid',
      '/group.php?mod=my&view=groupthread',
      '/forum.php?mod=group&fid=6&action=memberlist',
      '/forum.php?mod=post&action=newthread&fid=6',
      '/forum.php?mod=post&action=reply&tid=7',
      '/forum.php?mod=post&action=edit&tid=7&pid=8&cedit=yes',
      '/home.php?mod=spacecp&ac=blog&blogid=9',
      '/home.php?mod=spacecp&ac=friend&op=add&uid=8',
      '/home.php?mod=spacecp&ac=comment&op=edit&cid=9',
      '/thread-7-2-1.html',
      '/forum-6-2.html',
      '/article-4-2.html',
      '/blog-8-9.html',
      '/space-uid-8.html?do=profile',
    ];
    for (final shell in shells.entries) {
      for (final path in paths) {
        test('${shell.key} supplies evidence on $path', () {
          expect(
            parse(shell.value, sourceUri: origin.resolve(path))?.combined,
            ForumMessageAttentionState.present,
          );
        });
      }
      for (final path in <String>[
        '/home.php?mod=space&do=pm',
        '/home.php?mod=space&do=notice',
        '/home.php?mod=follow&do=follower',
        '/home.php?mod=space&do=follow',
        '/forum.php?mod=post&action=reply&replysubmit=yes',
        '/forum.php?mod=post&action=edit&inajax=1',
        '/home.php?mod=spacecp&ac=friend&op=addconfirm&key=opaque',
        '/home.php?mod=spacecp&ac=pm&op=checknewpm',
        '/plugin.php?id=unknown:page',
        '/space-uid-8.html',
        '/home.php?mod=space&do=index&uid=8&additional=removevlog',
      ]) {
        test('${shell.key} cannot rescue an excluded source $path', () {
          expect(parse(shell.value, sourceUri: origin.resolve(path)), isNull);
        });
      }
    }

    test('default desktop search without a message shell remains unknown', () {
      final source = attentionHtmlDocument('''
<div id="toptb"><div class="y">
  <strong><a href="home.php?mod=space">Viewer profile</a></strong>
</div></div>
<div class="threadlist"><p>Search results.</p></div>
''');
      expect(
        parse(source, sourceUri: origin.resolve('/search.php?mod=forum')),
        isNull,
      );
    });

    test('a supported route with a wrong viewer still cannot publish', () {
      expect(
        parse(
          mobileAttentionHtml(viewerUserId: '43', messageDot: true),
          sourceUri: origin.resolve('/misc.php?mod=tag&id=3'),
        ),
        isNull,
      );
    });
  });

  group('response trust and consumption boundaries', () {
    final inactive = mobileAttentionHtml();

    for (final trailer in <String>[
      '<script>var trailer = "</body></html>',
      '<style>/* </body></html>',
      '<textarea></body></html>',
      '<!-- </body></html>',
    ]) {
      test(
        'fake closing tags in unclosed markup do not complete a document: $trailer',
        () {
          expect(
            parse(inactive.replaceFirst('</body>\n</html>', trailer)),
            isNull,
          );
        },
      );
    }

    for (final fakeAssignment in <String>[
      "/* discuz_uid = '42' */",
      "// discuz_uid = '42'\n",
      r'''var text = " discuz_uid = '42'";''',
      r'''var text = `discuz_uid = '42'`;''',
    ]) {
      test(
        'viewer text outside executable assignments is not identity: $fakeAssignment',
        () {
          expect(
            parse(
              inactive.replaceFirst("var discuz_uid = '42';", fakeAssignment),
            ),
            isNull,
          );
        },
      );
    }

    test(
      'comments and string content do not duplicate a real viewer assignment',
      () {
        final observation = parse(
          mobileAttentionHtml(
            extraHead: r'''
<script>
/* discuz_uid = '43' */
// discuz_uid = '44'
var text = "discuz_uid = '45'";
var template = `discuz_uid = '46'`;
</script>
''',
          ),
        )!;
        expect(observation.viewerUserId, '42');
        expect(observation.combined, ForumMessageAttentionState.absent);
      },
    );

    test(
      'template-style comma-separated static variables retain viewer identity',
      () {
        final observation = parse(
          inactive.replaceFirst(
            "var discuz_uid = '42';",
            r'''var STYLEID = '1', STATICURL = 'static/', creditnotice = '<span class="credit">Forum credits</span><html-like text><html><head><body></body></html>', discuz_uid = '42', SITEURL = 'https://forum.example.test/';''',
          ),
        )!;
        expect(observation.viewerUserId, '42');
        expect(observation.combined, ForumMessageAttentionState.absent);
      },
    );

    for (final entry in <String, String>{
      'inert script':
          "<script type=\"text/plain\">var discuz_uid = '42';</script>",
      'module script':
          "<script type=\"module\">var discuz_uid = '42';</script>",
      'conditional assignment':
          "<script>if(false) var discuz_uid = '42';</script>",
      'later mutation': "<script>var discuz_uid = '42'; discuz_uid++;</script>",
      'escaped viewer literal':
          r'''<script>var discuz_uid = '\x34\x32';</script>''',
    }.entries) {
      test('${entry.key} does not establish a static template viewer', () {
        expect(
          parse(
            inactive.replaceFirst(
              "<script>var discuz_uid = '42';</script>",
              entry.value,
            ),
          ),
          isNull,
        );
      });
    }

    for (final entry in <String, String>{
      'missing head viewer': inactive.replaceFirst('discuz_uid', 'content_uid'),
      'guest viewer': mobileAttentionHtml(viewerUserId: '0'),
      'different viewer': mobileAttentionHtml(viewerUserId: '43'),
      'nondecimal viewer': mobileAttentionHtml(viewerUserId: '0x2a'),
      'duplicate viewer assignment': mobileAttentionHtml(
        extraHead: "<script>var discuz_uid = '42';</script>",
      ),
      'duplicate conflicting viewer assignment': mobileAttentionHtml(
        extraHead: "<script>var discuz_uid = '43';</script>",
      ),
      'body script impersonation': inactive
          .replaceFirst("var discuz_uid = '42';", '')
          .replaceFirst(
            '</body>',
            "<script>var discuz_uid = '42';</script></body>",
          ),
      'truncated HTML tail': inactive.replaceFirst('</html>', ''),
      'truncated body tail': inactive.replaceFirst('</body>', ''),
      'truncated head': inactive.replaceFirst('</head>', ''),
      'HTML fragment': mobileAttentionFooter(),
      'error page retaining footer': mobileAttentionHtml(
        content: '<div id="messagetext"><p>Request failed.</p></div>',
      ),
      'mobile error shell retaining footer': mobileAttentionHtml(
        content: '<div class="jump_c"><p>Request failed.</p></div>',
      ),
    }.entries) {
      test('${entry.key} yields no observation', () {
        expect(parse(entry.value), isNull);
      });
    }

    test('expected account must be a verified positive identity', () {
      for (final userId in <String>['', '0', '-42', '0x2a', 'unknown']) {
        expect(parse(inactive, expectedUserId: userId), isNull);
      }
    });

    for (final source in <String>[
      'https://external.example.test/forum.php',
      'http://forum.example.test/forum.php',
      'https://forum.example.test:8443/forum.php',
      'https://forum.example.test/member.php?mod=logging&action=login',
      'https://forum.example.test/home.php?mod=space&do=pm',
      'https://forum.example.test/home.php?mod=space&do=pm&page=2',
      'https://forum.example.test/home.php?mod=space&do=notice',
      'https://forum.example.test/home.php?mod=space&do=notice&view=mypost',
      'https://forum.example.test/home.php?mod=spacecp&ac=pm&op=checknewpm',
      'https://forum.example.test/forum.php?mod=forumdisplay&inajax=1',
      'https://forum.example.test/forum.php?mod=forumdisplay&mod=viewthread',
      'https://forum.example.test/api/mobile/index.php?module=forumindex',
    ]) {
      test('excluded source does not supply a snapshot: $source', () {
        expect(parse(inactive, sourceUri: Uri.parse(source)), isNull);
      });
    }

    test('viewed profile identity does not replace the response viewer', () {
      final observation = parse(
        inactive,
        sourceUri: Uri.parse(
          'https://forum.example.test/home.php?mod=space&uid=99&do=profile',
        ),
      )!;
      expect(observation.viewerUserId, '42');
    });

    test(
      'parsing is stateless across positive, unsupported and negative pages',
      () {
        expect(
          parse(mobileAttentionHtml(messageDot: true))?.combined,
          ForumMessageAttentionState.present,
        );
        expect(parse(mobileAttentionHtml(includeFooter: false)), isNull);
        expect(parse(inactive)?.combined, ForumMessageAttentionState.absent);
      },
    );
  });
}
