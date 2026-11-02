/// Generated, public corpus shared by the component and real-page benchmarks.
/// Keep the complex case intact even when a backend cannot yet render it.
final novelProfileSafeHtml = List<String>.filled(
  40,
  '<p>合成分页正文 mixed 123，只有公开生成文本，重复段落用于观察普通文字布局与换行。</p>',
).join();

final novelProfileComplexHtml =
    '<p><font face="serif">${List<String>.filled(120, '合成长复杂正文 mixed 123，A👨‍👩‍👧‍👦e\u0301🇨🇳中<ruby>注音<rt>zhuyin</rt></ruby>，连续边界与完整内容。').join()}</font></p>';

final novelProfileFixtures = <({String name, String html})>[
  (name: 'safe', html: novelProfileSafeHtml),
  (name: 'complex', html: novelProfileComplexHtml),
];

/// Separate corpus: do not silently change the established baseline samples.
/// Each paragraph remains below the renderer's 512-context admission limit.
final novelProfileRubyGapFixtures = <({String name, String html})>[
  (name: 'ruby-gaps-ltr', html: _rubyGaps()),
  (name: 'ruby-gaps-rtl', html: _rubyGaps(rtl: true)),
  (name: 'ruby-gaps-dense', html: _rubyGaps(ranks: 24, columns: 4)),
];

/// Source languages are a separate matrix: preserve prior baseline/gap inputs.
final novelProfileLanguageFixtures = <({String name, String html})>[
  (name: 'language-runs', html: _languageRuns()),
  (name: 'language-ruby-ltr', html: _languageRuby()),
  (name: 'language-ruby-rtl', html: _languageRuby(rtl: true)),
];

/// Real reader matrix for the admitted nested tree path. Keep established
/// corpora unchanged so their before/after performance comparisons stay valid.
final novelProfileNestedRubyFixtures = <({String name, String html})>[
  (name: 'ruby-nested-ltr', html: _nestedRuby()),
  (name: 'ruby-nested-rtl', html: _nestedRuby(rtl: true)),
];

// Deliberately exceeds the reader's issued-handle budget within one page.
// Keep this independent failure fixture when profiling the admitted corpus.
final novelProfileRubyGapOverflowHtml = _rubyGaps(
  ranks: 24,
  paragraphs: 3,
  annotationSize: 1.5,
);

List<({String name, String html})> novelMainPageProfileFixtures(
  String corpus,
) => switch (corpus) {
  'baseline' => novelProfileFixtures,
  'ruby-gaps' => novelProfileRubyGapFixtures,
  'language' => novelProfileLanguageFixtures,
  'ruby-nested' => novelProfileNestedRubyFixtures,
  _ => throw ArgumentError.value(corpus, 'corpus', 'Unknown profile corpus'),
};

String _nestedRuby({bool rtl = false}) => List.generate(
  48,
  (p) =>
      '<p dir="${rtl ? 'rtl' : 'ltr'}">${rtl ? 'نص تجريبي' : '合成嵌套正文'} $p '
      '<ruby><rb><ruby>漢😀<rt style="font-size:8px">kan</rt></ruby></rb>'
      '<rt style="font-size:8px">outer</rt></ruby>，'
      '<ruby>字<rt><ruby style="font-size:10px">に<rt style="font-size:6px">ni</rt></ruby></rt></ruby>，'
      '<ruby style="background:rgba(255,0,0,.2)"><rb><ruby>同<rt>in</rt></ruby></rb><rt>out</rt>'
      '<rb>根</rb><rt>flat</rt></ruby>，'
      '<ruby style="font-size:30px;line-height:2"><rb style="font-size:18px;line-height:1">'
      '<ruby>空<rt></rt></ruby></rb><rtc></rtc><rtc><rt></rt></rtc></ruby>。'
      '${rtl ? 'نهاية الفقرة.' : '正文、注音、来源与独立字体框。'}</p>',
).join();

Set<String>? novelProfileExpectedLanguages(String name) => switch (name) {
  'language-runs' => const {'ja', 'zh-Hans-CN', 'zh-Hant-TW', 'ko', 'und'},
  'language-ruby-ltr' => const {'ja', 'zh-Hant-TW', 'ko', 'und'},
  'language-ruby-rtl' => const {'ar', 'ja', 'zh-Hant-TW', 'ko', 'und'},
  _ => null,
};

String _rubyGaps({
  bool rtl = false,
  int ranks = 2,
  int paragraphs = 32,
  int columns = 6,
  double? annotationSize,
}) => List.generate(paragraphs, (p) {
  final direction = rtl ? 'rtl' : 'ltr';
  final groups = List.generate(ranks > 2 ? 1 : 4, (g) {
    final bases = List.generate(
      columns,
      (c) => '<rb>${rtl ? 'ب' : '合'}$c</rb>',
    ).join(' ');
    final annotations = List.generate(ranks, (r) {
      final boxes = List.generate(
        columns,
        (c) => '<rt>${rtl ? 'ن' : 'r'}$p$g$r$c</rt>',
      ).join(' ');
      return '<rtc style="font-size:${annotationSize ?? (ranks > 2 ? 8 : 10)}px;ruby-position:${r.isEven ? 'over' : 'under'}">$boxes</rtc>';
    }).join();
    return '<ruby>$bases$annotations</ruby>';
  }).join('，');
  return '<p dir="$direction">$groups</p>';
}).join();

String _languageRuns() => List.generate(
  48,
  (p) =>
      '<p lang="ja">日本語の漢字とかな $p '
      '<span lang="zh-Hans-CN">简体汉字与区域输入，</span>'
      '<span lang="zh-Hant-TW">繁體漢字與腳本輸入，</span>'
      '<span lang="ko">한글과 漢字，</span>'
      '<span lang="">unknown e\u0301 👨‍👩‍👧‍👦，</span>'
      '<span xml:lang="fr">日本語の親を継承する。</span></p>',
).join();

String _languageRuby({bool rtl = false}) => List.generate(
  48,
  (p) =>
      '<p dir="${rtl ? 'rtl' : 'ltr'}" lang="${rtl ? 'ar' : 'ja'}">'
      '${rtl ? 'نص عربي مع لغات مستقلة' : '日本語と独立した注音言語'} $p '
      '<ruby lang="zh-Hant-TW">繁體<rt lang="ja">はんたい</rt></ruby>，'
      '<ruby lang="ja">漢字<rt lang="ko">한자</rt></ruby>，'
      '<span lang="">unknown e\u0301</span> '
      '${rtl ? 'نهاية النص.' : '語言と方向を別々に保つ。'}</p>',
).join();
