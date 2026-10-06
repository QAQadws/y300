// Public chapter anchors from the supplied first-floor HTML, without user data.
const magicalGirlSourceTid = '574023';
const magicalGirlSourceSubject = '【星愿汉化组】【らる・ぶらん】魔法少女与前邪恶女干部 15-16';
const magicalGirlPreviousChapterAnchors = <(String, String)>[
  ('572807', '01'),
  ('572858', '02-03'),
  ('572919', '04'),
  ('572989', '05'),
  ('573089', '06'),
  ('573157', '07'),
  ('573228', '08'),
  ('573316', '09'),
  ('573440', '10'),
  ('573511', '11'),
  ('573585', '12'),
  ('573648', '13'),
  ('573932', '14'),
];
final magicalGirlPreviousChaptersHtml = <String>[
  '目录<br>',
  for (final chapter in magicalGirlPreviousChapterAnchors)
    '<font><font><a href="https://bbs.yamibo.com/thread-${chapter.$1}-1-1.html">'
        '${chapter.$2}</a></font></font>',
].join('&nbsp;&nbsp;');
