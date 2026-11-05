import 'package:html/parser.dart' as html_parser;
import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/adapters/thread_detail_html_parser.dart';

void main() {
  final parser = ThreadDetailHtmlParser(
    siteOrigin: Uri.parse('https://forum.example'),
  );

  for (final mobile in [false, true]) {
    test(
      'retains visible attachment entries on ${mobile ? 'mobile' : 'desktop'}',
      () {
        const body = '''正文
        <img src="/files/01.png">
        <div class="pattl"><dl class="tattl"><dt>正文内附件.txt</dt></dl></div>''';
        const attachments = '''
        <img id="aimg_20" file="/files/00.png">
        <div class="pattl">
          <ignore_js_op><dl class="tattl attm"><dt><img src="/icon.png"></dt><dd>
            <p><a href="forum.php?mod=attachment&amp;aid=21"
              onmouseover="showMenu()">01.png</a> <em>(3.46 MB, 下载次数: 2)</em></p>
            <div class="tip" style="display: none">保存到相册</div>
            <img id="aimg_21" aid="21" file="/files/01.png" src="/thumb.png">
          </dd></dl></ignore_js_op>
          <ignore_js_op><dl class="tattl attm"><dt></dt><dd>
            <p>02.png <em>(1 MB)</em></p>
            <img id="aimg_22" aid="22" zoomfile="/files/02.png" src="/thumb.png"
              alt="02.png" onclick="zoom()">
          </dd></dl></ignore_js_op>
          <div class="locked">请登录后查看其余附件</div>
          <script>openAttachment()</script>
          <p hidden><img id="aimg_23" file="/files/hidden.png">隐藏文件</p>
        </div>
        <div hidden><div class="pattl">隐藏附件列表</div></div>
        <img id="aimg_24" file="/files/03.png">''';
        final html = mobile
            ? '''<body id="forum"><div class="viewthread">
              <div class="plc" id="pid200">
                <div class="message">$body<div class="poll">投票控件</div></div>
                $attachments
              </div></div>'''
            : '''<div id="postlist"><div id="post_200"><div class="t_fsz">
              <table><tr><td class="t_f" id="postmessage_200">$body</td></tr></table>
              $attachments
              </div></div></div>''';
        final document = html_parser.parse(html);
        final detail = parser.parseDocument(
          document,
          fallbackTid: '100',
          fallbackPage: 1,
        );
        final message = html_parser.parseFragment(detail.posts.single.message);
        expect(message.querySelectorAll('.pattl'), hasLength(2));
        expect(message.querySelectorAll('.tattl'), hasLength(3));
        expect(message.querySelector('.locked')?.text, '请登录后查看其余附件');
        expect(message.querySelector('a')?.text, '01.png');
        expect(
          message.querySelector('a')?.attributes['href'],
          'forum.php?mod=attachment&aid=21',
        );
        expect(message.querySelector('em')?.text, '(3.46 MB, 下载次数: 2)');
        expect(
          message.querySelectorAll('[onclick], [onmouseover], script, .poll'),
          isEmpty,
        );
        expect(message.text, contains('正文内附件.txt'));
        expect(message.text, isNot(contains('保存到相册')));
        expect(message.text, isNot(contains('隐藏')));
        final images = message.querySelectorAll('img');
        expect(images.map((image) => image.attributes['src']), [
          '/files/01.png',
          '/files/00.png',
          '/files/02.png',
          '/files/03.png',
        ]);
        expect(images[2].attributes['aid'], '22');
        expect(images[2].attributes['alt'], '02.png');
        expect(document.querySelector('#aimg_21'), isNotNull);
        expect(document.querySelector('a[onmouseover]'), isNotNull);
      },
    );
  }
}
