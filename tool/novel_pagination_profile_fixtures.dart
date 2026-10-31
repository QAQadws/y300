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
