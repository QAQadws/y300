import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/services/novel_same_thread_catalog_extractor.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';

void main() {
  group('NovelSameThreadCatalogExtractor', () {
    const extractor = NovelSameThreadCatalogExtractor();

    test('extracts same-thread findpost links as pid chapters', () {
      final entries = extractor.extract(
        threadTid: '521519',
        opAuthorId: '1',
        posts: <ThreadPost>[
          ThreadPost(
            pid: '40213901',
            author: '楼主A',
            authorId: '1',
            message: '''
<a href="https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=521519&amp;pid=40213901">目录</a>
<a href="https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=521519&amp;pid=40213902">Episode 1</a>
<a href="https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=521519&amp;pid=40213904">Episode 2</a>
''',
            number: 1,
            isFirst: true,
            dateline: '2026-05-03',
          ),
        ],
      );

      expect(entries.map((entry) => entry.pid), <String>[
        '40213902',
        '40213904',
      ]);
      expect(entries.map((entry) => entry.title), <String>[
        'Episode 1',
        'Episode 2',
      ]);
    });

    test('ignores cross-thread, non-op and late-floor links', () {
      final entries = extractor.extract(
        threadTid: '521519',
        opAuthorId: '1',
        posts: <ThreadPost>[
          ThreadPost(
            pid: '1',
            author: '楼主A',
            authorId: '1',
            message: '''
<a href="https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=999999&amp;pid=1">跨帖</a>
<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&amp;tid=521519">普通主题链接</a>
''',
            number: 1,
            isFirst: true,
            dateline: '',
          ),
          ThreadPost(
            pid: '2',
            author: '路人',
            authorId: '2',
            message: '''
<a href="https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=521519&amp;pid=40213902">Episode 1</a>
<a href="https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=521519&amp;pid=40213904">Episode 2</a>
''',
            number: 2,
            isFirst: false,
            dateline: '',
          ),
          ThreadPost(
            pid: '11',
            author: '楼主A',
            authorId: '1',
            message: '''
<a href="https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=521519&amp;pid=40213905">Episode 3</a>
<a href="https://bbs.yamibo.com/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=521519&amp;pid=40213906">Episode 4</a>
''',
            number: 11,
            isFirst: false,
            dateline: '',
          ),
        ],
      );

      expect(entries, isEmpty);
    });
  });
}
