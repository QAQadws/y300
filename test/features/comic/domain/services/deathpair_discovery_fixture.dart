// Only the public chapter links from the supplied first-floor HTML are retained.
const deathpairSourceTid = '575649';
const deathpairFinalTid = '575651';
const deathpairSourceSubject =
    '【受祝福的因果律协会汉化组】[中村汚濁]圣少女默示录 DEATHPAIR 第30幕 这就是，我少女时期的物语';
const deathpairFinalSubject =
    '（漏图部分已补全）【受祝福的因果律协会汉化组】[中村汚濁]圣少女默示录 DEATHPAIR 终幕 平常的一天';
const deathpairChapterTids = <String>[
  '561619',
  '561834',
  '562430',
  '562797',
  '563516',
  '564279',
  '564787',
  '566306',
  '568072',
  '568763',
  '569996',
  '570879',
  '571628',
  '574712',
  '574771',
  '574860',
  '574894',
  '574923',
  '574973',
  '575013',
  '575058',
  '575080',
  '575117',
  '575196',
  '575311',
  '575350',
  '575646',
  '575647',
  '575648',
  deathpairSourceTid,
];
const deathpairPreviousChaptersHtml = '''
<font color="#000000">前期回顾：</font><br />
<a href="https://bbs.yamibo.com/thread-561619-1-1.html" target="_blank">第一幕</a>
<a href="https://bbs.yamibo.com/thread-561834-1-1.html" target="_blank">第二幕</a>
<a href="https://bbs.yamibo.com/thread-562430-1-1.html" target="_blank">第三幕</a>
<a href="https://bbs.yamibo.com/thread-562797-1-1.html" target="_blank">第四幕</a>
<a href="https://bbs.yamibo.com/thread-563516-1-1.html" target="_blank">第五幕</a>
<a href="https://bbs.yamibo.com/thread-564279-1-1.html" target="_blank">第六幕</a>
<a href="https://bbs.yamibo.com/thread-564787-1-1.html" target="_blank">第七幕</a>
<a href="https://bbs.yamibo.com/thread-566306-1-1.html" target="_blank">第八幕</a>
<a href="https://bbs.yamibo.com/thread-568072-1-1.html" target="_blank">第九幕</a>
<a href="https://bbs.yamibo.com/thread-568763-1-1.html" target="_blank">第十幕</a>
<a href="https://bbs.yamibo.com/thread-569996-1-1.html" target="_blank">第十一幕</a>
<a href="https://bbs.yamibo.com/thread-570879-1-1.html" target="_blank">第十二幕</a>
<font color="#000000"><a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=571628&amp;highlight=%E5%9C%A3%E5%B0%91%E5%A5%B3" target="_blank">第十三幕</a></font>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=574712&amp;page=1#pid41599893" target="_blank">第十四幕</a>
<a href="https://bbs.yamibo.com/thread-574771-1-1.html" target="_blank">第十五幕</a><br />
<a href="https://bbs.yamibo.com/thread-574860-1-1.html" target="_blank">第十六幕</a>
<a href="https://bbs.yamibo.com/thread-574894-1-1.html" target="_blank">第十七幕</a>
<a href="https://bbs.yamibo.com/thread-574923-1-1.html" target="_blank">第十八幕</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=574973&amp;page=1#pid41604327" target="_blank">第十九幕</a>
<a href="https://bbs.yamibo.com/thread-575013-1-1.html" target="_blank">第二十幕</a>
<a href="https://bbs.yamibo.com/thread-575058-1-1.html" target="_blank">第二十一幕</a>
<a href="https://bbs.yamibo.com/thread-575080-1-1.html" target="_blank">第二十二幕</a>
<a href="https://bbs.yamibo.com/thread-575117-1-1.html" target="_blank">第二十三幕</a>
<a href="https://bbs.yamibo.com/thread-575196-1-1.html" target="_blank">第二十四幕</a>
<a href="https://bbs.yamibo.com/thread-575311-1-1.html" target="_blank">第二十五幕</a>
<a href="https://bbs.yamibo.com/thread-575350-1-1.html" target="_blank">第二十六幕</a><br />
<a href="https://bbs.yamibo.com/thread-575646-1-1.html" target="_blank">第二十七幕</a>
<a href="https://bbs.yamibo.com/thread-575647-1-1.html" target="_blank">第二十八幕</a>
<a href="https://bbs.yamibo.com/thread-575648-1-1.html" target="_blank">第二十九幕</a><br />
''';
