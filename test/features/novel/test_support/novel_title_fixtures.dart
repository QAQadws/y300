/// App HTML/pagination fixtures and a test-only bridge to the title corpus.
library;

import '../../../../packages/content_title_core/test/fixtures/novel_title_fixtures.dart'
    as title_cases;

export '../../../../packages/content_title_core/test/fixtures/novel_title_fixtures.dart'
    show NovelTitleFixture, novelTitleFixtures;

/// Synthetic UTF-8 forum documents used by the hybrid pagination pipeline.
const novelPaginationFixtureTitles = <String, String>{
  'ruby': '注音',
  'background_color': '文字背景色',
  'collapse_directory': '折叠目录',
  'text_color_size': '字颜色字号',
};

/// Adds App HTML to the canonical pure chapter-title case without copying it.
class NovelChapterTitleFixture {
  const NovelChapterTitleFixture({
    required this.titleCase,
    required this.rawHtml,
  });

  final title_cases.NovelChapterTitleCase titleCase;
  final String rawHtml;

  String get id => titleCase.id;
  String get normalizedCandidate => titleCase.normalizedCandidate;
  String get expectedTitle => titleCase.expectedTitle;
}

const novelChapterTitleFixtures = <NovelChapterTitleFixture>[
  NovelChapterTitleFixture(
    titleCase: title_cases.decimalActNumberAfterEditNoticeFixture,
    rawHtml: '''
      <i class="pstatus"> 本帖最后由 没有太阳的晴日 于 2026-1-18 08:47 编辑 </i><br>
      <br>
      <div align="center"><font face="宋体">ACT13.5　现实中真的会发生这种事吗？</font></div>
      <font face="Arial">&nbsp;&nbsp;</font><br>
      <font face="Arial">「到啦——！」</font><br>
    ''',
  ),
];
