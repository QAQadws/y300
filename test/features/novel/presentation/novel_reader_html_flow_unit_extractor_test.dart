import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_flow_unit_extractor.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  const extractor = DefaultNovelReaderHtmlFlowUnitExtractor();

  test('extracts stable semantic units from the prepared HTML document', () {
    final document = _prepare(
      '<p id="first">第一<strong>段</strong>'
      '<a href="thread-101-1-1.html">链接</a></p>'
      '<blockquote>引用正文</blockquote>'
      '<hr>'
      '<table><tbody><tr><td>表格正文</td></tr></tbody></table>',
    );

    final units = extractor.extract(
      episodeId: 'episode-1',
      renderDocument: document,
    );

    expect(units, hasLength(4));
    expect(units.first.unitId, 'episode-1:novel-html-id-first-0');
    expect(units.first.breakability, NovelReaderFlowUnitBreakability.text);
    expect(units.first.html, contains('<strong>段</strong>'));
    expect(units.first.html, contains('thread-101-1-1.html'));
    expect(units.first.startAnchor.nodeId, units.first.endAnchor.nodeId);
    expect(units.first.startAnchor.textOffset, 0);
    expect(units.first.endAnchor.textOffset, '第一段链接'.runes.length);
    expect(units[1].breakability, NovelReaderFlowUnitBreakability.text);
    expect(units[2].breakability, NovelReaderFlowUnitBreakability.atomicWidget);
    expect(units[3].breakability, NovelReaderFlowUnitBreakability.atomicWidget);
    for (final unit in units) {
      expect(
        html_parser.parseFragment(unit.html).nodes,
        isNotEmpty,
        reason: unit.unitId,
      );
    }
  });

  test('keeps whole-chapter readable image indices after unit extraction', () {
    final document = _prepare(
      '<p>正文前'
      '<img src="data/attachment/forum/first.jpg">正文后</p>'
      '<img src="data/attachment/forum/second.jpg">'
      '<img src="static/image/smiley/default/smile.gif">',
    );

    final units = extractor.extract(
      episodeId: 'episode-images',
      renderDocument: document,
    );
    final extractedIndices = units
        .expand((unit) => unit.imageIndices)
        .toList(growable: false);

    expect(document.sequence.entries, hasLength(2));
    expect(document.sequence.entries.map((entry) => entry.index), <int>[0, 1]);
    expect(extractedIndices, <int>[0, 1]);
    expect(units.first.imageIndices, <int>[0]);
    expect(units[1].breakability, NovelReaderFlowUnitBreakability.blockImage);
    expect(units[1].imageIndices, <int>[1]);
    expect(units.last.imageIndices, isEmpty);
  });

  test('duplicate blocks receive deterministic occurrence identities', () {
    final document = _prepare('<p>重复正文</p><p>重复正文</p>');

    final first = extractor.extract(
      episodeId: 'episode-duplicates',
      renderDocument: document,
    );
    final second = extractor.extract(
      episodeId: 'episode-duplicates',
      renderDocument: document,
    );

    expect(first.map((unit) => unit.unitId), second.map((unit) => unit.unitId));
    expect(first[0].unitId, endsWith('-0'));
    expect(first[1].unitId, endsWith('-1'));
    expect(first[0].unitId, isNot(first[1].unitId));
  });

  test('empty prepared HTML creates one deterministic empty unit', () {
    final document = _prepare('<p>   </p>');

    final units = extractor.extract(
      episodeId: 'episode-empty',
      renderDocument: document,
    );

    expect(units, hasLength(1));
    expect(units.single.unitId, 'episode-empty:empty');
    expect(units.single.html, isEmpty);
    expect(units.single.imageIndices, isEmpty);
  });
}

ForumHtmlPreparedRenderDocument _prepare(String html) {
  return const DefaultForumHtmlRenderPreparer().prepare(
    html: html,
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: _theme,
    sourceId: 'flow-unit-test',
    threadId: '100',
    imageCacheOwnerId: '100',
  );
}

const _theme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFF4EAD7),
  foreground: Color(0xFF4C3A21),
  link: Color(0xFF6A55A3),
  quoteSurface: Color(0xFFE8D8B8),
  quoteForeground: Color(0xFF8B7355),
  codeSurface: Color(0xFFEFE0C4),
  codeForeground: Color(0xFF4C3A21),
);
