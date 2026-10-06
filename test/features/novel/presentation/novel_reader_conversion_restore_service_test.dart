import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_conversion_position.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_conversion_restore_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_flow_unit_extractor.dart';

void main() {
  const service = NovelReaderConversionRestoreService();

  test(
    'maps a semantic code-point boundary through inline DOM and normalization',
    () {
      const oldHtml = '<p>前&nbsp;&nbsp;👩‍👩‍👧‍👦<b>臺</b><br>國e\u0301尾</p>';
      const newHtml = '<p>前&nbsp;&nbsp;👩‍👩‍👧‍👦<b>台</b><br>国e\u0301尾</p>';
      final old = _chapter(oldHtml);
      final next = _chapter(newHtml);
      final oldAnchor = old.flowUnits.single.startAnchor.copyWith(
        textOffset: '前 👩‍👩‍👧‍👦臺\n國'.runes.length,
      );
      final anchor = service.project(
        source: _position(oldHtml, old, oldAnchor),
        rawHtml: oldHtml,
        conversionIdentity: 'toSimplified',
        target: next,
      )!;
      expect(anchor.nodeId, next.flowUnits.single.startAnchor.nodeId);
      expect(
        anchor.textIdentity,
        next.flowUnits.single.startAnchor.textIdentity,
      );
      expect(anchor.textIdentity, isNot(oldAnchor.textIdentity));
      expect(anchor.textOffset, '前 👩‍👩‍👧‍👦台\n国'.runes.length);
    },
  );

  test(
    'keeps the second duplicate paragraph through its actual layout unit',
    () {
      const html = '<p>臺重複。</p><p>臺重複。</p><p>尾段。</p>';
      final old = _chapter(html);
      final next = _chapter(html.replaceAll('臺重複', '台重复'));
      expect(old.flowUnits[1].startAnchor.nodeId, startsWith('novel-html-'));
      final anchor = service.project(
        source: _position(
          html,
          old,
          old.flowUnits[1].startAnchor.copyWith(textOffset: 2),
        ),
        rawHtml: html,
        conversionIdentity: 'toSimplified',
        target: next,
      )!;
      expect(anchor.nodeId, next.flowUnits[1].startAnchor.nodeId);
      expect(anchor.nodeId, isNot(next.flowUnits[0].startAnchor.nodeId));
      expect(anchor.textOffset, 2);
    },
  );

  test(
    'projects a complex multi-block unit rather than guessing semantic nodes',
    () {
      const html =
          '<div><p>臺甲</p><p>國乙</p><table><tr><td>臺尾</td></tr></table></div>';
      final old = _chapter(html);
      final next = _chapter(html.replaceAll('臺', '台').replaceAll('國', '国'));
      final anchor = service.project(
        source: _position(
          html,
          old,
          old.flowUnits.single.startAnchor.copyWith(textOffset: 3),
        ),
        rawHtml: html,
        conversionIdentity: 'toSimplified',
        target: next,
      )!;
      expect(anchor.nodeId, next.flowUnits.single.startAnchor.nodeId);
      expect(anchor.textOffset, 3);
      expect(
        anchor.textIdentity,
        next.flowUnits.single.startAnchor.textIdentity,
      );
    },
  );

  test(
    'length-changing conversion preserves the unchanged suffix boundary',
    () {
      const html = '<p>臺前滑鼠尾巴。</p>';
      final old = _chapter(html);
      final next = _chapter('<p>台前鼠标设备尾巴。</p>');
      final anchor = service.project(
        source: _position(
          html,
          old,
          old.flowUnits.single.startAnchor.copyWith(textOffset: 4),
        ),
        rawHtml: html,
        conversionIdentity: 'toSimplified',
        target: next,
      )!;
      expect(anchor.textOffset, 6);
    },
  );

  test(
    'length-changing replacement uses its beginning for an uncertain interior',
    () {
      const html = '<p>前滑鼠尾。</p>';
      final old = _chapter(html);
      final anchor = service.project(
        source: _position(
          html,
          old,
          old.flowUnits.single.startAnchor.copyWith(textOffset: 2),
        ),
        rawHtml: html,
        conversionIdentity: 'toSimplified',
        target: _chapter('<p>前鼠标设备尾。</p>'),
      )!;
      expect(anchor.textOffset, 1);
    },
  );

  test(
    'does not split an extended grapheme when projecting rune boundaries',
    () {
      const html = '<p>👩‍👩‍👧‍👦臺尾</p>';
      final old = _chapter(html);
      final next = _chapter('<p>👩‍👩‍👧‍👦台尾</p>');
      final anchor = service.project(
        source: _position(
          html,
          old,
          old.flowUnits.single.startAnchor.copyWith(textOffset: 3),
        ),
        rawHtml: html,
        conversionIdentity: 'toSimplified',
        target: next,
      )!;
      expect(anchor.textOffset, 0);
    },
  );

  test('reverse conversion uses its verified original display', () {
    const raw = '<p>臺國。</p>';
    final old = _chapter('<p>台国。</p>');
    final next = _chapter(raw);
    final anchor = service.project(
      source: _position(
        raw,
        old,
        old.flowUnits.single.startAnchor.copyWith(textOffset: 1),
        mode: 'toSimplified',
      ),
      rawHtml: raw,
      conversionIdentity: 'none',
      target: next,
    )!;
    expect(anchor.textIdentity, next.flowUnits.single.startAnchor.textIdentity);
    expect(anchor.textOffset, 1);
  });

  for (final caseName in [
    'changed source',
    'changed chapter',
    'same mode',
    'future format',
    'wrong identity',
    'changed DOM',
    'out of coverage',
  ]) {
    test('rejects $caseName without guessing a converted location', () {
      const html = '<p>臺正文。</p><p>國尾。</p>';
      final old = _chapter(html);
      var anchor = old.flowUnits.first.startAnchor;
      if (caseName == 'future format') {
        anchor = anchor.copyWith(formatVersion: 37);
      }
      if (caseName == 'wrong identity') {
        anchor = anchor.copyWith(textIdentity: 'edited');
      }
      if (caseName == 'out of coverage') {
        anchor = anchor.copyWith(textOffset: 999);
      }
      final next = _chapter(
        caseName == 'changed DOM'
            ? '<p>台正文。</p><div>国尾。</div>'
            : '<p>台正文。</p><p>国尾。</p>',
        episodeId: caseName == 'changed chapter' ? 'other' : 'episode',
      );
      expect(
        service.project(
          source: _position(html, old, anchor),
          rawHtml: caseName == 'changed source' ? '$html<p>新增</p>' : html,
          conversionIdentity: caseName == 'same mode' ? 'none' : 'toSimplified',
          target: next,
        ),
        isNull,
      );
    });
  }

  test(
    'large source projection can transfer data to the background worker',
    () async {
      final html = '<p>${List.filled(4000, '臺國').join()}</p>';
      final old = _chapter(html);
      final next = _chapter(html.replaceAll('臺', '台').replaceAll('國', '国'));
      final result = await service.projectInBackground(
        source: _position(
          html,
          old,
          old.flowUnits.single.startAnchor.copyWith(textOffset: 4000),
        ),
        rawHtml: html,
        conversionIdentity: 'toSimplified',
        target: next,
      );
      expect(result!.textOffset, 4000);
      expect(
        result.textIdentity,
        next.flowUnits.single.startAnchor.textIdentity,
      );
    },
  );
}

NovelReaderConversionPosition _position(
  String raw,
  NovelReaderPreparedChapter chapter,
  NovelReaderTextAnchor anchor, {
  String mode = 'none',
}) => NovelReaderConversionPosition(
  rawHtml: raw,
  conversionIdentity: mode,
  chapter: chapter,
  anchor: anchor,
);

NovelReaderPreparedChapter _chapter(
  String html, {
  String episodeId = 'episode',
}) {
  final rendered = const DefaultForumHtmlRenderPreparer().prepare(
    html: html,
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: const ForumHtmlThemeContext(
      brightness: ForumHtmlBrightness.light,
      surface: Colors.white,
      foreground: Colors.black,
      link: Colors.blue,
      quoteSurface: Colors.grey,
      quoteForeground: Colors.black,
      codeSurface: Colors.white,
      codeForeground: Colors.black,
    ),
    sourceId: episodeId,
    threadId: '100',
    imageCacheOwnerId: '100',
  );
  final semantic = const DiscuzNovelReaderDocumentParser().parse(
    episodeId: episodeId,
    rawHtml: html,
    fallbackParagraphs: const [],
  );
  return NovelReaderPreparedChapter(
    episodeId: episodeId,
    contentHash: html,
    html: rendered.preparedHtml,
    renderDocument: rendered,
    flowUnits: const DefaultNovelReaderHtmlFlowUnitExtractor().extract(
      episodeId: episodeId,
      renderDocument: rendered,
      semanticDocument: semantic,
    ),
    themeSignature: rendered.themeSignature,
    imageDimensionRevision: 0,
    convertedTextNodeCount: 0,
  );
}
