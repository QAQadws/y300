import 'package:html/parser.dart' as html_parser;
import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/adapters/thread_detail_html_parser.dart';

void main() {
  final parser = ThreadDetailHtmlParser(
    siteOrigin: Uri.parse('https://forum.example'),
  );

  for (final mobile in [false, true]) {
    test(
      'preserves mechanical collapse bodies on ${mobile ? 'mobile' : 'desktop'}',
      () {
        const body = '''
          <div class="showcollapse_box">
            <div class="showcollapse_title">目录</div>
            <div class="showcollapse_content" style="display: none">
              可展开正文
              <div class="showcollapse_box">
                <div class="showcollapse_title">子目录</div>
                <div class="showcollapse_content" style="display:none!important">
                  可展开的子正文
                </div>
              </div>
              <span class="jammer">混淆文本</span>
              <span style="display:none">普通隐藏文字</span>
            </div>
          </div>
          <div class="showcollapse_content" style="display:none">孤立隐藏正文</div>
          <div class="showcollapse_box">
            <div class="showcollapse_title">隐藏正文的标题</div>
            <div class="showcollapse_content" hidden style="display:none">显式隐藏正文</div>
          </div>
          <div class="showcollapse_box">
            <div class="showcollapse_content" style="display:none">缺少标题</div>
          </div>
          <div class="showcollapse_box">
            <div class="showcollapse_title">重复正文的标题</div>
            <div class="showcollapse_content" style="display:none">不匹配正文一</div>
            <div class="showcollapse_content" style="display:none">不匹配正文二</div>
          </div>
          <div style="display:none">
            <div class="showcollapse_box">
              <div class="showcollapse_title">隐藏容器中的标题</div>
              <div class="showcollapse_content" style="display:none">隐藏容器中的正文</div>
            </div>
          </div>''';
        final html = mobile
            ? '''<body id="forum"><div class="viewthread">
              <div class="plc" id="pid200"><div class="message">$body</div></div>
              </div>'''
            : '''<div id="postlist"><div id="post_200"><table>
              <tr><td class="t_f" id="postmessage_200">$body</td></tr>
              </table></div></div>''';
        final result = parser.parse(html, fallbackTid: '100', fallbackPage: 1);
        final message = html_parser.parseFragment(result.posts.single.message);

        final bodies = message.querySelectorAll('.showcollapse_content');
        expect(bodies, hasLength(2));
        expect(bodies.first.text, contains('可展开正文'));
        expect(bodies.last.text.trim(), '可展开的子正文');
        expect(bodies.first.attributes['style'], 'display: none');
        expect(message.text, isNot(contains('混淆文本')));
        expect(message.text, isNot(contains('普通隐藏文字')));
        expect(message.text, isNot(contains('隐藏容器中的标题')));
      },
    );
  }
}
