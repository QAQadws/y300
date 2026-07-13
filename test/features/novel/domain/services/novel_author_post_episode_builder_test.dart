import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/services/novel_author_post_episode_builder.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  const builder = DefaultNovelAuthorPostEpisodeBuilder();

  test('rejects posts whose local author identity does not match', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(authorId: '999', message: '<p>不应导入。</p>'),
      authorFilteredPage: 1,
      orderIndex: 0,
    );

    expect(draft, isNull);
  });

  test('skips a first post that only contains intro and catalog metadata', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        isFirst: true,
        number: 1,
        message: '''
          <p>简介</p><p>这只是作品简介。</p><p>目录</p>
          <p><a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=2">第一章</a></p>
        ''',
      ),
      authorFilteredPage: 1,
      orderIndex: 0,
    );

    expect(draft, isNull);
  });

  test('builds stable episode data from a publisher post', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        pid: '40213902',
        number: 2,
        message: '<p>雨终于停了。她推开窗。</p><p>第二段正文</p>',
      ),
      authorFilteredPage: 3,
      orderIndex: 7,
    );

    expect(draft, isNotNull);
    expect(draft?.episodeId, 'novel:55:521519:40213902');
    expect(draft?.sourceTid, '521519');
    expect(draft?.sourcePid, '40213902');
    expect(draft?.sourcePage, 3);
    expect(draft?.orderIndex, 7);
    expect(draft?.episodeTitle, '雨终于停了。');
    expect(draft?.plainText, contains('第二段正文'));
    expect(draft?.paragraphs, contains('第二段正文'));
  });

  test('expands verified attach placeholders and accepts image-only posts', () {
    final draft = builder.build(
      novelId: 'novel:55:521519',
      tid: '521519',
      publisherId: '406769',
      post: _post(
        pid: '40213903',
        number: 3,
        message: '[attach]88[/attach]',
        attachments: const <ForumPostAttachmentImage>[
          ForumPostAttachmentImage(
            aid: '88',
            url: 'https://bbs.yamibo.com/',
            attachment: 'data/attachment/forum/cover.jpg',
            filename: 'cover.jpg',
            attachimg: '1',
            ext: 'jpg',
          ),
        ],
      ),
      authorFilteredPage: 1,
      orderIndex: 2,
    );

    expect(draft, isNotNull);
    expect(draft?.episodeTitle, '第 3 章');
    expect(draft?.rawHtml, contains('<img src='));
    expect(draft?.imageUrls, hasLength(1));
  });
}

ThreadPost _post({
  String pid = '40213901',
  String authorId = '406769',
  String message = '',
  int number = 1,
  bool isFirst = false,
  List<ForumPostAttachmentImage> attachments =
      const <ForumPostAttachmentImage>[],
}) {
  return ThreadPost(
    pid: pid,
    author: 'INCSKY16',
    authorId: authorId,
    message: message,
    number: number,
    isFirst: isFirst,
    dateline: '2026-07-13',
    attachmentImages: attachments,
  );
}
