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
  _ => throw ArgumentError.value(corpus, 'corpus', 'Unknown profile corpus'),
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
