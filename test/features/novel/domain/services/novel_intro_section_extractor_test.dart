import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/services/novel_intro_section_extractor.dart';

void main() {
  const extractor = DefaultNovelIntroSectionExtractor();

  test('双边界命中：取 [简介行, 目录行)，目录行不包含', () {
    const html = '''
<p>无关引子</p>
<p>简介：这是一段</p>
<p>多行的</p>
<p>故事简介。</p>
<p>目录</p>
<p>第一章 ...</p>
<p>第二章 ...</p>
''';
    final intro = extractor.extract(firstPostHtml: html);
    expect(intro, isNotNull);
    expect(intro, contains('简介：这是一段'));
    expect(intro, contains('多行的'));
    expect(intro, contains('故事简介。'));
    expect(intro, isNot(contains('目录')));
    expect(intro, isNot(contains('第一章')));
    expect(intro, isNot(contains('无关引子')));
  });

  test('只命中 contents：把目录以上整段当作简介', () {
    const html = '''
<p>本作背景</p>
<p>主要角色：A、B、C</p>
<p>contents</p>
<p>第一章 ...</p>
''';
    final intro = extractor.extract(firstPostHtml: html);
    expect(intro, isNotNull);
    expect(intro, contains('本作背景'));
    expect(intro, contains('主要角色：A、B、C'));
    expect(intro, isNot(contains('contents')));
    expect(intro, isNot(contains('第一章')));
  });

  test('只命中 intro：提取到正文结尾', () {
    const html = '''
<p>简介</p>
<p>balabala</p>
<p>第一章 ...</p>
''';
    expect(extractor.extract(firstPostHtml: html), '简介\nbalabala\n第一章 ...');
  });

  test('双 marker 都没命中：返回 null', () {
    const html = '''
<p>第一章 开始</p>
<p>正文 A</p>
''';
    expect(extractor.extract(firstPostHtml: html), isNull);
  });

  test('contents 出现在 intro 之前：视作未命中（顺序异常）', () {
    const html = '''
<p>contents</p>
<p>第一章 ...</p>
<p>简介</p>
<p>balabala</p>
''';
    final intro = extractor.extract(firstPostHtml: html);
    // intro=2, contents=0 → 不命中双边界；走单 contents 分支：取 [0, 0) → 空 → null
    expect(intro, isNull);
  });

  test('繁体 markers 也命中', () {
    const html = '''
<p>介紹</p>
<p>故事大綱</p>
<p>目錄</p>
<p>第一話</p>
''';
    final intro = extractor.extract(firstPostHtml: html);
    expect(intro, isNotNull);
    expect(intro, contains('介紹'));
    expect(intro, contains('故事大綱'));
    expect(intro, isNot(contains('目錄')));
  });

  test('br 标签转换成换行，行内匹配 marker', () {
    const html = '简介：这是简介<br>balabala<br>电梯<br>第一章 ...';
    final intro = extractor.extract(firstPostHtml: html);
    expect(intro, isNotNull);
    expect(intro, contains('简介：这是简介'));
    expect(intro, contains('balabala'));
    expect(intro, isNot(contains('电梯')));
  });

  test('顶层 strong 和 br 不会被后续折叠 div 吞掉', () {
    const html = '''
<strong>作品名</strong><br>
<strong>简介</strong><br>
这是第一句简介。<br>
这是第二句简介。<br>
<div class="showcollapse_box">
  <div class="showcollapse_title">剧透提示</div>
  <div class="showcollapse_content">
    剧透内容
    <div class="showcollapse_gather">收起</div>
  </div>
</div><br>
<strong>目录：</strong><br>
<a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=2">ACT01</a>
''';

    final intro = extractor.extract(firstPostHtml: html);

    expect(intro, isNotNull);
    expect(intro, startsWith('简介\n这是第一句简介。'));
    expect(intro, contains('这是第二句简介。'));
    expect(intro, contains('剧透内容'));
    expect(intro, isNot(contains('收起')));
    expect(intro, isNot(contains('目录')));
    expect(intro, isNot(contains('ACT01')));
  });

  test('全空 HTML 返回 null', () {
    expect(extractor.extract(firstPostHtml: ''), isNull);
    expect(extractor.extract(firstPostHtml: '   '), isNull);
  });

  test('intro 与 contents 紧邻时返回单一 intro 标记段', () {
    const html = '''
<p>简介</p>
<p>目录</p>
''';
    // 仅一行 marker，filter 掉空白后 selected 实际只剩 "简介" 一段 → 返回 "简介"
    // —— 这是合规行为：用户可视为一个标记保留也无妨；但 join 后非空。
    final intro = extractor.extract(firstPostHtml: html);
    expect(intro, '简介');
  });

  test('超长内容被截断到 maxLength', () {
    final body = StringBuffer('<p>简介</p>');
    for (var i = 0; i < 50; i++) {
      // 必须每段唯一，否则 ForumPostDomExtractor.extractParagraphTexts
      // 会去重，无法构造长内容触发截断。
      body.write('<p>line-$i ${'a' * 100}</p>');
    }
    body.write('<p>目录</p>');
    final intro = extractor.extract(firstPostHtml: body.toString());
    expect(intro, isNotNull);
    expect(intro!.length, lessThanOrEqualTo(1200));
    // 必须确实是被截断了 —— 50 段每段 ~110 字符，远超 1200。
    expect(intro.length, 1200);
  });

  test('自定义 maxLength 参数生效', () {
    const customExtractor = DefaultNovelIntroSectionExtractor(maxLength: 10);
    const html = '''
<p>简介</p>
<p>这是一段比较长的简介内容</p>
<p>目录</p>
''';
    final intro = customExtractor.extract(firstPostHtml: html);
    expect(intro, isNotNull);
    expect(intro!.length, lessThanOrEqualTo(10));
  });
}
