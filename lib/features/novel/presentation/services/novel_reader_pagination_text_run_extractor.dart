import 'package:flutter/material.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_text_run.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

final class NovelReaderPaginationTextRunExtractor {
  const NovelReaderPaginationTextRunExtractor({
    this.styleResolver = const DefaultForumHtmlTextStyleResolver(),
  });

  final ForumHtmlTextStyleResolver styleResolver;

  List<NovelReaderPaginationTextRun> extract({
    required NovelReaderClassifiedPaginationAtom classifiedAtom,
    required TextStyle baseStyle,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
  }) {
    if (classifiedAtom.route != NovelReaderPaginationRoute.safeText) {
      throw ArgumentError.value(
        classifiedAtom.route,
        'classifiedAtom',
        'Only safe text atoms can produce TextPainter runs.',
      );
    }
    final fragment = html_parser.parseFragment(classifiedAtom.atom.html);
    final runs = <NovelReaderPaginationTextRun>[];
    final cursor = _TextRunCursor(0);
    for (var index = 0; index < fragment.nodes.length; index += 1) {
      _extractNode(
        fragment.nodes[index],
        path: '$index',
        atom: classifiedAtom,
        parentStyle: baseStyle,
        baseStyle: baseStyle,
        inheritedHref: null,
        preferences: preferences,
        theme: theme,
        cursor: cursor,
        output: runs,
      );
    }
    return List<NovelReaderPaginationTextRun>.unmodifiable(runs);
  }

  void _extractNode(
    html_dom.Node node, {
    required String path,
    required NovelReaderClassifiedPaginationAtom atom,
    required TextStyle parentStyle,
    required TextStyle baseStyle,
    required String? inheritedHref,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required _TextRunCursor cursor,
    required List<NovelReaderPaginationTextRun> output,
  }) {
    if (node is html_dom.Text) {
      if (node.data.isEmpty) {
        return;
      }
      final length = node.data.runes.length;
      output.add(
        NovelReaderPaginationTextRun(
          text: node.data,
          style: parentStyle,
          startAnchor: _anchorAt(atom, cursor.offset),
          endAnchor: _anchorAt(atom, cursor.offset + length),
          htmlNodeId: '${atom.atom.atomId}:$path',
          href: inheritedHref,
          sourceStart: cursor.offset,
          sourceEnd: cursor.offset + length,
        ),
      );
      cursor.offset += length;
      return;
    }
    if (node is! html_dom.Element) {
      return;
    }
    if (node.localName?.toLowerCase() == 'br') {
      output.add(
        NovelReaderPaginationTextRun(
          text: '\n',
          style: parentStyle,
          startAnchor: _anchorAt(atom, cursor.offset),
          endAnchor: _anchorAt(atom, cursor.offset + 1),
          htmlNodeId: '${atom.atom.atomId}:$path',
          href: inheritedHref,
          isParagraphBreak: true,
          sourceStart: cursor.offset,
          sourceEnd: cursor.offset + 1,
        ),
      );
      cursor.offset++;
      return;
    }
    final resolved = styleResolver.resolve(
      element: node,
      parentStyle: parentStyle,
      baseStyle: baseStyle,
      preferences: preferences,
      theme: theme,
    );
    if (!resolved.isSupported) {
      throw StateError(
        'Safe text atom contains an unresolved style: ${resolved.failure}.',
      );
    }
    final href = node.localName?.toLowerCase() == 'a'
        ? node.attributes['href']?.trim()
        : inheritedHref;
    for (var index = 0; index < node.nodes.length; index += 1) {
      _extractNode(
        node.nodes[index],
        path: '$path.$index',
        atom: atom,
        parentStyle: resolved.style,
        baseStyle: baseStyle,
        inheritedHref: href?.isEmpty == true ? null : href,
        preferences: preferences,
        theme: theme,
        cursor: cursor,
        output: output,
      );
    }
  }

  NovelReaderTextAnchor _anchorAt(
    NovelReaderClassifiedPaginationAtom atom,
    int sourceOffset,
  ) =>
      atom.atom.sourceAnchorProjection?.anchorAtSourceRune(sourceOffset) ??
      atom.atom.startAnchor.copyWith(
        textOffset: atom.atom.startAnchor.textOffset + sourceOffset,
      );
}

final class _TextRunCursor {
  _TextRunCursor(this.offset);

  int offset;
}
