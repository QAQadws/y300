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

final novelProfileLongTextFixtures = <({String name, String html})>[
  (name: 'long-text-10k', html: _longText(100)),
  (name: 'long-text-100k', html: _longText(1000)),
];

String _longText(int paragraphs) => List.generate(paragraphs, (index) {
  final text = '第 ${index + 1} 段正文。'.padRight(100, '文');
  return '<p>$text</p>';
}).join();

/// Finite S6 format matrix. Keep the established performance baselines intact;
/// these exercise ordinary forum containers and single-level annotations only.
final novelProfileSemanticFixtures = <({String name, String html})>[
  (name: 'semantic-blocks', html: _semanticBlocks()),
  (name: 'semantic-ruby-tight', html: _semanticRuby()),
  (name: 'semantic-code', html: _semanticCode()),
];

String _semanticBlocks() =>
    '<i class="pstatus">本帖最后由 Synthetic Editor 于 2026-10-31 12:00 编辑</i><br><br>'
    '${List.generate(12, (i) => '<h${i % 6 + 1}>第${i + 1}节 标题</h${i % 6 + 1}>'
        '<div style="padding:4px 6px;background:#f1e0c0">'
        '<p><font face="UnavailableAuthorFont" color="#9c2020">有色正文</font>，'
        '<b>粗体</b>、<i>斜体</i>、<u>下划线</u>与<del>删除线</del>。'
        'A<sup>2</sup> 和 H<sub>2</sub>O 保持原文与基线。</p>'
        '<div class="quote"><div><blockquote><b>引用 $i</b><br>'
        '继续阅读，核对引用续页与原始文字。'
        '<ruby><rb>正文</rb><rt>せいぶん</rt></ruby>。</blockquote></div></div>'
        '<ol start="8"><li>项目甲 $i，继续阅读以核对编号。'
        '<ul><li>子项目</li></ul></li><li value="12">项目乙</li><li></li></ol>'
        '</div><hr>').join()}';

String _semanticRuby() => List.generate(
  32,
  (i) =>
      '<p style="line-height:1.2">第${i + 1}段，普通正文与 '
      '<ruby><rb><font face="UnavailableAuthorFont" color="#9c2020">漢字</font></rb>'
      '<rp>(</rp><rt><span style="color:#204090">かんじ</span></rt><rp>)</rp></ruby>'
      ' 单层注音混排。<b>实际字体包络</b>与父行保持一致，'
      '不裁切，不把注音放入普通复制窗口。</p>',
).join();

String _semanticCode() =>
    '<p>代码前，<code>inline_code()</code> 与普通文字共用来源。</p>'
    '<pre>  spaces\tand_tab\n\ntrailing_line\n</pre>'
    '<div class="blockcode"><div id="code_S6a"><ol>'
    '${List.generate(32, (i) => '<li>  line_${i + 1}();\t// 保留空白\n'
        '    ${List.filled(i == 0 ? 20 : 2, 'long_word_').join()}tail;</li>').join()}'
    '</ol></div><em onclick="copycode(\$(\'code_S6a\'));">复制代码</em></div>'
    '<p>代码后，作者同名文字：复制代码。</p>';

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

/// Mixed RB/RT children use real intrinsic parents. Keep this separate from
/// closed-tree corpora so earlier performance measurements remain comparable.
final novelProfileMixedNestedRubyFixtures = <({String name, String html})>[
  (name: 'ruby-mixed-nested-ltr', html: _mixedNestedRuby()),
  (name: 'ruby-mixed-nested-rtl', html: _mixedNestedRuby(rtl: true)),
];

/// General outer columns retain their own mixed bases, annotation spans and
/// real gaps. Anonymous RTC text deliberately exercises actual spanning.
final novelProfileNestedColumnFixtures = <({String name, String html})>[
  (name: 'ruby-nested-columns-ltr', html: _nestedColumns()),
  (name: 'ruby-nested-columns-rtl', html: _nestedColumns(rtl: true)),
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
  'long-text' => novelProfileLongTextFixtures,
  'semantic' => novelProfileSemanticFixtures,
  'ruby-gaps' => novelProfileRubyGapFixtures,
  'language' => novelProfileLanguageFixtures,
  'ruby-nested' => novelProfileNestedRubyFixtures,
  'ruby-mixed-nested' => novelProfileMixedNestedRubyFixtures,
  'ruby-nested-columns' => novelProfileNestedColumnFixtures,
  _ => throw ArgumentError.value(corpus, 'corpus', 'Unknown profile corpus'),
};

String _nestedColumns({bool rtl = false}) => List.generate(
  32,
  (p) =>
      '<p dir="${rtl ? 'rtl' : 'ltr'}">${rtl ? 'نص تجريبي' : '合成原始多列'} $p '
      '<ruby><rb>前<ruby>漢😀<rt style="font-size:8px">kan</rt></ruby>後</rb>'
      '<rb>列</rb><rtc style="font-size:8px"><rt>first</rt><rt>second</rt></rtc></ruby>，'
      '<ruby style="background:rgba(255,0,0,.2)"><rb><ruby>同<rt>in</rt></ruby></rb>'
      '<rb>根</rb><rtc style="font-size:10px">shared annotation</rtc>'
      '<rtc style="font-size:8px;ruby-position:under"><rt>下</rt><rt>层</rt></rtc></ruby>，'
      '<ruby><rb><ruby>中<rt>latin</rt></ruby></rb>\n<rb>文</rb>'
      '<rtc style="font-size:8px"><rt>先<ruby>に<rt>ni</rt></ruby>後</rt> <rt>end</rt></rtc></ruby>。'
      '${rtl ? 'نهاية الفقرة.' : '原始分列、跨列注音与空白来源。'}</p>',
).join();

String _mixedNestedRuby({bool rtl = false}) => List.generate(
  32,
  (p) =>
      '<p dir="${rtl ? 'rtl' : 'ltr'}">${rtl ? 'نص تجريبي' : '合成混合嵌套'} $p '
      '<ruby><rb>前<ruby>漢😀<rt style="font-size:8px">kan</rt></ruby>後</rb>'
      '<rt style="font-size:8px">outer</rt></ruby>，'
      '<ruby>字<rt>先<ruby style="font-size:10px">に'
      '<rt style="font-size:6px">ni</rt></ruby>後</rt></ruby>，'
      '<ruby style="background:rgba(255,0,0,.2)"><rb>左'
      '<ruby style="background:rgba(0,255,0,.2)"><rb>同</rb><rb>根</rb>'
      '<rtc><rt rbspan="2">shared</rt></rtc></ruby>右</rb><rt>outside</rt></ruby>，'
      '<ruby style="font-size:30px;line-height:1.35"><rb style="font-size:18.5px;line-height:1.15">'
      '前<ruby>空<rt></rt></ruby>後</rb><rt style="font-size:7.5px">end</rt></ruby>。'
      '${rtl ? 'نهاية الفقرة.' : '原始来源与实际原生父段落保持独立。'}</p>',
).join();

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
