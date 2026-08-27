import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_sample_document.dart';

void main() {
  test('forum HTML prototype sample manifest is stable', () {
    expect(forumHtmlPrototypeSamples, hasLength(6));

    expect(
      forumHtmlPrototypeSamples.map((sample) => sample.id),
      containsAll(<String>[
        'ruby',
        'background_color',
        'collapse_directory',
        'text_color_size',
        'jitter_test',
        'thread_527325_blank_body',
      ]),
    );

    expect(
      forumHtmlPrototypeSamples.map((sample) => sample.id).toSet(),
      hasLength(forumHtmlPrototypeSamples.length),
    );
    expect(
      forumHtmlPrototypeSamples.map((sample) => sample.assetPath).toSet(),
      hasLength(forumHtmlPrototypeSamples.length),
    );

    expect(
      forumHtmlPrototypeSamples.map((sample) => sample.sourceDocPath),
      containsAll(<String>[
        'docs/html/特殊格式/注音.html',
        'docs/html/特殊格式/文字背景色.html',
        'docs/html/特殊格式/折叠目录.html',
        'docs/html/特殊格式/字颜色字号.html',
        'docs/html/特殊格式/抖动测试.html',
        'docs/html/特殊格式/无法进入帖子_527325.html',
      ]),
    );
    expect(
      forumHtmlPrototypeSamples
          .singleWhere((sample) => sample.id == 'jitter_test')
          .renderMode,
      ForumHtmlSampleRenderMode.threadDetail,
    );
    expect(
      forumHtmlPrototypeSamples
          .singleWhere((sample) => sample.id == 'thread_527325_blank_body')
          .renderMode,
      ForumHtmlSampleRenderMode.threadDetail,
    );
  });
}
