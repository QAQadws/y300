import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';

void main() {
  group('YamiboTagPageParsing', () {
    const parsing = YamiboTagPageParsing();

    test('normalizes Yamibo tag catalog url to thread page one', () {
      expect(
        parsing.normalizeCatalogEntryUrl(
          'https://bbs.yamibo.com/misc.php?mod=tag&id=21920',
        ),
        'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1',
      );
    });

    test('preserves explicit tag catalog page when normalizing', () {
      expect(
        parsing.normalizeCatalogEntryUrl(
          'misc.php?mod=tag&id=21920&type=thread&page=3',
        ),
        'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=3',
      );
    });

    test('resolves relative urls and decodes html ampersands', () {
      expect(
        parsing.resolveUrl(
          'misc.php?mod=tag&amp;id=21920&amp;type=thread',
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1',
        ),
        'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread',
      );
    });

    test('extracts tid from pretty and query thread urls', () {
      expect(
        parsing.extractTidFromThreadUrl(
          'https://bbs.yamibo.com/thread-558227-1-1.html',
        ),
        '558227',
      );
      expect(
        parsing.extractTidFromThreadUrl(
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=558976',
        ),
        '558976',
      );
    });

    test('recognizes only valid Yamibo tag catalog urls', () {
      expect(
        parsing.isTagCatalogUrl(
          'https://bbs.yamibo.com/misc.php?mod=tag&id=21920',
        ),
        isTrue,
      );
      expect(
        parsing.isTagCatalogUrl('https://bbs.yamibo.com/misc.php?mod=tag'),
        isFalse,
      );
      expect(
        parsing.isTagCatalogUrl(
          'https://example.com/misc.php?mod=tag&id=21920',
        ),
        isFalse,
      );
    });

    test('rejects action and external urls that merely contain tid', () {
      expect(
        parsing.extractTidFromThreadUrl(
          'https://bbs.yamibo.com/misc.php?mod=misc&action=viewratings&tid=558976',
        ),
        isNull,
      );
      expect(
        parsing.extractTidFromThreadUrl(
          'https://example.com/forum.php?mod=viewthread&tid=558976',
        ),
        isNull,
      );
    });

    test('parses current total next and previous pagination urls', () {
      final document = html_parser.parse('''
<div class="pg">
<a href="misc.php?mod=tag&id=21920&type=thread&amp;page=1" class="prev">上一页</a>
<strong>2</strong>
<label><span title="共 4 页"> / 4 页</span></label>
<a href="misc.php?mod=tag&id=21920&type=thread&amp;page=3" class="nxt">下一页</a>
</div>
''');

      final pagination = parsing.parsePagination(
        document: document,
        baseUrl:
            'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=2',
      );

      expect(pagination.currentPage, 2);
      expect(pagination.totalPages, 4);
      expect(
        pagination.previousPageUrl,
        'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1',
      );
      expect(
        pagination.nextPageUrl,
        'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=3',
      );
    });

    test('withPage keeps tag catalog thread type', () {
      final url = parsing.withPage(
        Uri.parse('https://bbs.yamibo.com/misc.php?mod=tag&id=21920'),
        5,
      );

      expect(
        url.toString(),
        'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&page=5&type=thread',
      );
    });
  });
}
