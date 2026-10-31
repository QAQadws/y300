/// Synthetic Discuz/reader inputs shared by renderer conformance tests.
/// Contains no captured posts, resource credentials or application fixtures.
final class ForumBodyCase {
  const ForumBodyCase(this.id, this.html, this.visibleTokens);

  final String id;
  final String html;
  final List<String> visibleTokens;
}

const forumBodyCases = <ForumBodyCase>[
  ForumBodyCase('paragraphs', '<p>合成章节甲。</p><p>これは試験です。</p>', [
    '合成章节甲。',
    'これは試験です。',
  ]),
  ForumBodyCase('top-level-breaks', '第一行<br>第二行<br><br>末行', [
    '第一行',
    '第二行',
    '末行',
  ]),
  ForumBodyCase('entities', '<p>甲&nbsp;&nbsp;乙 &amp; 丙&#x3000;丁</p>', [
    '甲',
    '乙',
    '&',
    '丙',
    '丁',
  ]),
  ForumBodyCase(
    'v1-fonts',
    '<font face="MissingAuthorFont" size="5">'
        '局部大字<strong>作者强调</strong></font><br><font size="2">小字</font>',
    ['局部大字', '作者强调', '小字'],
  ),
  ForumBodyCase(
    'author-layout',
    '<p style="font-size:12px;line-height:28px;'
        'text-indent:2em;text-align:right;margin:4px 0">作者段落</p>',
    ['作者段落'],
  ),
  ForumBodyCase(
    'tracking',
    '<p style="letter-spacing:1px;word-spacing:2px">'
        '字距与 word spacing</p>',
    ['字距与 word spacing'],
  ),
  ForumBodyCase(
    'nested-inline',
    '<p><b>粗体<i>斜体</i></b><u>下划线</u>'
        '<strike>删除线</strike><font color="#9c2020" '
        'style="background-color:rgb(252,244,207)">底色</font></p>',
    ['粗体', '斜体', '下划线', '删除线', '底色'],
  ),
  ForumBodyCase(
    'edit-status',
    '<i class="pstatus">合成编辑提示</i><br><br>'
        '<p>编辑后的正文</p>',
    ['合成编辑提示', '编辑后的正文'],
  ),
  ForumBodyCase(
    'links',
    '<p>正文<a href="forum.php?mod=viewthread&amp;tid=100">'
        '站内链接</a><a href="https://example.invalid/long/path">外链</a></p>',
    ['正文', '站内链接', '外链'],
  ),
  ForumBodyCase('ruby', '<p><ruby>漢字<rt>かんじ</rt></ruby>与普通文字</p>', [
    '漢字',
    'かんじ',
    '与普通文字',
  ]),
  ForumBodyCase(
    'quote-list',
    '<div class="quote"><blockquote>引用正文'
        '</blockquote></div><ul type="A" class="litype_3">'
        '<li>列表甲<ul><li>嵌套项</li></ul></li><li>列表乙</li></ul>',
    ['引用正文', '列表甲', '嵌套项', '列表乙'],
  ),
  ForumBodyCase(
    'code',
    '<div class="blockcode"><ol><li>  first();</li>'
        '<li>second();</li></ol></div>',
    ['first();', 'second();'],
  ),
  ForumBodyCase(
    'table',
    '<table><tr><td rowspan="2">跨行格</td>'
        '<td>第一格</td></tr><tr><td>第二格</td></tr></table>',
    ['跨行格', '第一格', '第二格'],
  ),
  ForumBodyCase(
    'collapse',
    '<div class="showcollapse_box" id="sample-fold">'
        '<div class="showcollapse_title">合成折叠</div>'
        '<div class="showcollapse_content"><p>折叠内正文</p></div></div>',
    ['合成折叠'],
  ),
  ForumBodyCase(
    'resources',
    '<p>图前<img src="https://example.invalid/a.png" '
        'width="80" height="40" aid="10">图后</p>'
        '<p>表情<img src="https://example.invalid/static/image/smiley/a.gif" '
        'smilieid="1" width="16" height="16"></p>',
    ['图前', '图后', '表情'],
  ),
  ForumBodyCase(
    'attachment-lock',
    '<ignore_js_op><dl class="tattl">'
        '<dt>附件</dt><dd><a href="forum.php?mod=attachment&amp;aid=10">'
        'sample.txt</a></dd></dl></ignore_js_op>'
        '<div class="locked">服务器返回的权限提示</div>',
    ['附件', 'sample.txt', '服务器返回的权限提示'],
  ),
  ForumBodyCase(
    'float',
    '<span style="float:left;margin-right:5px">浮动块'
        '</span><p>围绕文字</p>',
    ['浮动块', '围绕文字'],
  ),
  ForumBodyCase('malformed', '<p>未闭合<b>嵌套</p><div>后续正文', ['未闭合', '嵌套', '后续正文']),
  ForumBodyCase(
    'unicode-layout',
    '<p dir="rtl">مرحبا 123 中文 👩‍💻 e\u0301</p>',
    ['مرحبا', '123', '中文', '👩‍💻', 'e\u0301'],
  ),
];

/// Bounded test generation; lengths are UTF-16 code units, not source offsets.
String forumBodyStressHtml(int textCodeUnits, {bool singleParagraph = false}) {
  if (textCodeUnits < 0) throw RangeError.value(textCodeUnits);
  final buffer = StringBuffer();
  var remaining = textCodeUnits;
  while (remaining > 0) {
    final count = remaining < 100 ? remaining : 100;
    if (!singleParagraph) buffer.write('<p>');
    buffer.write(List.filled(count, '文').join());
    if (!singleParagraph) buffer.write('</p>');
    remaining -= count;
  }
  return singleParagraph ? '<p>$buffer</p>' : buffer.toString();
}
