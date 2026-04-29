import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

// 测试说明：
// 1) 当 message 中包含 [attach]aid[/attach] 占位时，应被替换为对应附件的 <img> 标签；
// 2) 当 attachments 中存在未在 message 中占位的图片时，应追加到 trailingImageUrls 列表。
// 这些测试使用内联模拟数据，验证 ThreadPost.buildContent() 的行为。

void main() {
  group('ThreadPostContent', () {
    test('replaces attachment placeholder with image html', () {
      // 测试占位替换：message 中含有 [attach]1572764[/attach]，应生成 img 标签
      final post = ThreadPost.fromJson({
        'pid': '1',
        'author': 'alice',
        'authorid': '1',
        'message': '图片 [attach]1572764[/attach] end',
        'number': '1',
        'first': '1',
        'dateline': 'today',
        'attachments': {
          '1572764': {
            'aid': '1572764',
            'attachimg': '1',
            'url': 'data/attachment/forum/',
            'attachment': '202604/20/pic.jpg',
          },
        },
      });

      final content = post.buildContent();

      expect(
        content.html,
        contains(
          '<img src="${AppConfig.siteBaseUrl}/data/attachment/forum/202604/20/pic.jpg" />',
        ),
      );
      expect(content.trailingImageUrls, isEmpty);
    });

    test('appends image urls when no placeholder found', () {
      // 测试追加尾部图片：message 中无占位，但 attachments 含图片，应出现在 trailingImageUrls
      final post = ThreadPost.fromJson({
        'pid': '2',
        'author': 'bob',
        'authorid': '2',
        'message': '<p>no placeholder</p>',
        'number': '2',
        'first': '0',
        'dateline': 'today',
        'attachments': {
          '1572': {
            'attachimg': '1',
            'url': 'data/attachment/forum/',
            'attachment': '202604/20/another.jpg',
          },
        },
      });

      final content = post.buildContent();

      expect(content.html, contains('<p>no placeholder</p>'));
      expect(
        content.trailingImageUrls,
        [
          '${AppConfig.siteBaseUrl}/data/attachment/forum/202604/20/another.jpg',
        ],
      );
    });
  });
}
