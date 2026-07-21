import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_extractor.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  const extractor = NovelReaderPaginationAtomExtractor();

  test('isolates readable images while preserving surrounding text', () async {
    final chapter = await _prepare(
      '<p>正文前<img src="data/attachment/forum/first.jpg">正文后</p>'
      '<img src="data/attachment/forum/second.jpg">'
      '<img src="static/image/smiley/default/smile.gif">',
    );

    final atoms = extractor.extract(chapter);

    expect(atoms.map((atom) => atom.kind), <NovelReaderPaginationAtomKind>[
      NovelReaderPaginationAtomKind.text,
      NovelReaderPaginationAtomKind.image,
      NovelReaderPaginationAtomKind.text,
      NovelReaderPaginationAtomKind.image,
      NovelReaderPaginationAtomKind.inlineImage,
    ]);
    expect(atoms[0].html, contains('正文前'));
    expect(atoms[0].html, isNot(contains('first.jpg')));
    expect(atoms[1].imageIndices, <int>[0]);
    expect(atoms[1].isIsolatedImage, isTrue);
    expect(atoms[1].html, contains('first.jpg'));
    expect(atoms[2].html, contains('正文后'));
    expect(atoms[2].html, isNot(contains('first.jpg')));
    expect(atoms[3].imageIndices, <int>[1]);
    expect(atoms[4].imageIndices, isEmpty);
    expect(atoms[4].isIsolatedImage, isFalse);
    for (final atom in atoms) {
      expect(html_parser.parseFragment(atom.html).nodes, isNotEmpty);
    }
  });

  test('keeps deterministic atom identities and text offsets', () async {
    final chapter = await _prepare(
      '<p>前文<img src="data/attachment/forum/first.jpg">后文</p>',
    );

    final first = extractor.extract(chapter);
    final second = extractor.extract(chapter);

    expect(first.map((atom) => atom.atomId), second.map((atom) => atom.atomId));
    expect(first[0].startAnchor.textOffset, 0);
    expect(first[0].endAnchor.textOffset, '前文'.runes.length);
    expect(first[1].startAnchor.textOffset, 0);
    expect(first[1].endAnchor.textOffset, 0);
    expect(first[1].startAnchor.nodeId, contains(':image-0'));
    expect(first[2].startAnchor.textOffset, '前文'.runes.length);
    expect(first[2].endAnchor.textOffset, '前文后文'.runes.length);
  });

  test('keeps images inside atomic widgets structurally intact', () async {
    final chapter = await _prepare(
      '<table><tbody><tr><td>表格前'
      '<img src="data/attachment/forum/first.jpg">表格后'
      '</td></tr></tbody></table>',
    );

    final atoms = extractor.extract(chapter);

    expect(atoms, hasLength(1));
    expect(atoms.single.kind, NovelReaderPaginationAtomKind.atomicWidget);
    expect(atoms.single.isIsolatedImage, isFalse);
    expect(atoms.single.imageIndices, <int>[0]);
    expect(atoms.single.html, contains('<table'));
    expect(atoms.single.html, contains('first.jpg'));
  });

  test('does not create blank text atoms around an image', () async {
    final chapter = await _prepare(
      '<p>正文<img src="data/attachment/forum/first.jpg">   </p>',
    );

    final atoms = extractor.extract(chapter);

    expect(atoms, hasLength(2));
    expect(atoms.first.kind, NovelReaderPaginationAtomKind.text);
    expect(atoms.last.kind, NovelReaderPaginationAtomKind.image);
  });

  test(
    'classifies top-level text and br nodes without complex widgets',
    () async {
      final chapter = await _prepare('第一行<br>\r\n　　第二行<br>\r\n第三行<br>');

      final atoms = extractor.extract(chapter);

      expect(atoms.map((atom) => atom.kind), <NovelReaderPaginationAtomKind>[
        NovelReaderPaginationAtomKind.inlineText,
        NovelReaderPaginationAtomKind.spacer,
        NovelReaderPaginationAtomKind.inlineText,
        NovelReaderPaginationAtomKind.spacer,
        NovelReaderPaginationAtomKind.inlineText,
        NovelReaderPaginationAtomKind.spacer,
      ]);
      expect(atoms[0].html, '第一行');
      expect(atoms[2].html, '　　第二行');
      expect(atoms[4].html, '第三行');
      expect(
        atoms.where((atom) => atom.html.contains(RegExp(r'[\r\n]'))),
        isEmpty,
      );
      expect(
        atoms.where(
          (atom) => atom.kind == NovelReaderPaginationAtomKind.spacer,
        ),
        hasLength(3),
      );
    },
  );

  test('keeps Discuz div lines and drops whitespace-only divs', () async {
    final chapter = await _prepare(
      '<div align="left"><font face="Arial">第一行</font></div>'
      '<div align="left"><font face="Arial">&nbsp;&nbsp;</font></div>'
      '<div align="left"><font face="Arial">　　</font></div>'
      '<p>语义段落</p>',
    );

    final atoms = extractor.extract(chapter);

    expect(atoms, hasLength(2));
    expect(atoms.first.kind, NovelReaderPaginationAtomKind.lineBlock);
    expect(atoms.first.html, contains('第一行'));
    expect(atoms.last.kind, NovelReaderPaginationAtomKind.text);
    expect(atoms.last.html, contains('语义段落'));
  });
}

Future<NovelReaderPreparedChapter> _prepare(String html) {
  const episode = NovelEpisodeItem(
    episodeId: 'atom-episode',
    novelId: 'atom-novel',
    sourceTid: '100',
    episodeTitle: 'Atom test',
    orderIndex: 0,
  );
  return const DefaultNovelReaderHtmlPreparationService().prepare(
    rawHtml: html,
    episode: episode,
    preferences: NovelHtmlReaderPreferencesAdapter().map(
      NovelReaderPreferences.defaults(),
    ),
    theme: _theme,
    sourceId: episode.episodeId,
    threadId: episode.sourceTid,
    imageCacheOwnerId: episode.sourceTid,
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
