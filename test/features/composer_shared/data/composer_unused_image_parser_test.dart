import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/data/services/composer_unused_image_parser.dart';

void main() {
  const parser = ComposerUnusedImageParser();
  final sourceUri = Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=ajax&action=imagelist&posttime=0',
  );

  test('parses ordered images, descriptions, and HTML entities', () {
    final result = parser.parse(
      body: _envelope('''
<table cellspacing="2" cellpadding="2" class="imgl"><tr>
  ${_cell('1629686', title: 'a&amp;b.jpg', description: '甲&amp;乙')}
  ${_cell('1629685', title: 'second.jpg')}
  <td width="25%"></td>
</tr></table>
'''),
      sourceUri: sourceUri,
      hasConfirmedLoggedInSession: true,
    );

    expect(result.map((image) => image.aid), <String>['1629686', '1629685']);
    expect(result.first.fileName, 'a&b.jpg');
    expect(result.first.description, '甲&乙');
    expect(result.first.thumbnailUri.host, 'bbs.yamibo.com');
    expect(result.first.thumbnailUri.queryParameters['aid'], '1629686');
    expect(result.first.thumbnailUri.queryParameters['size'], '300x300');
  });

  test('deduplicates identical aids without changing first-seen order', () {
    final cell = _cell('7', title: 'same.jpg');
    final result = parser.parse(
      body: _envelope('<table class="imgl"><tr>$cell$cell</tr></table>'),
      sourceUri: sourceUri,
      hasConfirmedLoggedInSession: true,
    );

    expect(result, hasLength(1));
    expect(result.single.aid, '7');
  });

  test('accepts authoritative empty catalogs only for confirmed sessions', () {
    expect(
      parser.parse(
        body: _envelope(''),
        sourceUri: sourceUri,
        hasConfirmedLoggedInSession: true,
      ),
      isEmpty,
    );
    expect(
      () => parser.parse(
        body: _envelope(''),
        sourceUri: sourceUri,
        hasConfirmedLoggedInSession: false,
      ),
      throwsFormatException,
    );
    expect(
      parser.parse(
        body: _envelope('<table class="imgl"><tr><td></td></tr></table>'),
        sourceUri: sourceUri,
        hasConfirmedLoggedInSession: true,
      ),
      isEmpty,
    );
  });

  test('rejects WAF, login HTML, and unknown non-empty fragments', () {
    for (final body in <String>[
      '<!doctype html><title>Aliyun WAF</title>',
      '<html><a href="member.php?mod=logging">登录</a></html>',
      _envelope('<div>unexpected</div>'),
      _envelope(
        '<div>unexpected</div><table class="imgl"><tr>${_cell('1')}</tr></table>',
      ),
    ]) {
      expect(
        () => parser.parse(
          body: body,
          sourceUri: sourceUri,
          hasConfirmedLoggedInSession: true,
        ),
        throwsFormatException,
      );
    }
  });

  test('rejects malformed, external, mismatched, and conflicting entries', () {
    final invalidCells = <String>[
      _cell('0'),
      _cell('1', imageAid: '2'),
      _cell(
        '1',
        source:
            'https://example.com/forum.php?mod=image&amp;aid=1&amp;size=300x300',
      ),
      '${_cell('1', title: 'one.jpg')}${_cell('1', title: 'two.jpg')}',
    ];
    for (final cells in invalidCells) {
      expect(
        () => parser.parse(
          body: _envelope('<table class="imgl"><tr>$cells</tr></table>'),
          sourceUri: sourceUri,
          hasConfirmedLoggedInSession: true,
        ),
        throwsFormatException,
      );
    }
  });

  test('rejects a redirected catalog from a non-Yamibo origin', () {
    expect(
      () => parser.parse(
        body: _envelope('<table class="imgl"><tr>${_cell('1')}</tr></table>'),
        sourceUri: Uri.parse('https://example.com/forum.php'),
        hasConfirmedLoggedInSession: true,
      ),
      throwsFormatException,
    );
  });

  test('rejects a same-origin redirect away from the catalog endpoint', () {
    expect(
      () => parser.parse(
        body: _envelope('<table class="imgl"><tr>${_cell('1')}</tr></table>'),
        sourceUri: Uri.parse(
          'https://bbs.yamibo.com/member.php?mod=logging&action=login',
        ),
        hasConfirmedLoggedInSession: true,
      ),
      throwsFormatException,
    );
  });
}

String _envelope(String payload) => '<root><![CDATA[$payload]]></root>';

String _cell(
  String aid, {
  String? imageAid,
  String? source,
  String title = 'image.jpg',
  String description = '',
}) {
  final resolvedImageAid = imageAid ?? aid;
  final resolvedSource =
      source ??
      'forum.php?mod=image&amp;aid=$resolvedImageAid&amp;size=300x300&amp;key=secret';
  return '''
<td id="image_td_$aid">
  <a id="imageattach$aid" title="$title">
    <img id="image_$resolvedImageAid" src="$resolvedSource" />
  </a>
  <p class="mtn mbn xi2">
    <a href="javascript:;" onclick="delImgAttach($aid,1);return false;">删除</a>
  </p>
  <p class="imgf">
    <input type="text" class="px xg2" value="描述" />
    <input name="attachnew[$aid][description]" value="$description" />
  </p>
  <p class="mtn">
    <input type="hidden" id="albumaid_$aid" name="albumaid[]" value="" />
    <label><input type="checkbox" value="$aid" />保存到相册</label>
  </p>
</td>
''';
}
