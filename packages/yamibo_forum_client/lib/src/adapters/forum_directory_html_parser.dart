// ignore_for_file: public_member_api_docs

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../contracts/forum_directory.dart';
import '../url/forum_uri_resolver.dart';

final class ForumDirectoryHtmlParser {
  ForumDirectoryHtmlParser({required Uri siteOrigin})
    : _resolver = ForumUriResolver(siteOrigin: siteOrigin);

  final ForumUriResolver _resolver;

  ForumDirectoryData parse(String source) {
    final document = html_parser.parse(source);
    final forumList = document.querySelector('.forumlist');
    if (forumList == null) {
      throw const FormatException('forum_directory_root_missing');
    }
    final sections = <ForumDirectorySection>[];
    for (final header in forumList.querySelectorAll('.subforumshow')) {
      final section = _targetSection(
        forumList,
        header.attributes['href']?.trim(),
      );
      if (section == null || section.id == 'sub-forum-myfav') continue;
      final identity = _sectionIdentity(header, section);
      final title = _clean(header.querySelector('h2')?.text ?? header.text);
      final forums = _forums(section);
      if (identity.isEmpty || title.isEmpty || forums.isEmpty) continue;
      sections.add(
        ForumDirectorySection(
          identity: identity,
          title: title,
          forums: List<ForumDirectoryForum>.unmodifiable(forums),
        ),
      );
    }
    final data = ForumDirectoryData(
      sections: List<ForumDirectorySection>.unmodifiable(sections),
    );
    _validate(data);
    return data;
  }

  html_dom.Element? _targetSection(html_dom.Element root, String? selector) {
    if (selector == null || selector.isEmpty) return null;
    try {
      return root.querySelector(selector);
    } catch (_) {
      return null;
    }
  }

  String _sectionIdentity(html_dom.Element header, html_dom.Element section) {
    final target = header.attributes['href']?.trim() ?? '';
    if (target.startsWith('#') && target.length > 1) {
      return target.substring(1);
    }
    return section.id.trim();
  }

  List<ForumDirectoryForum> _forums(html_dom.Element section) {
    final result = <ForumDirectoryForum>[];
    for (final anchor in section.querySelectorAll('a.murl')) {
      final uri = _resolve(anchor.attributes['href']);
      final fid = uri == null ? null : _fid(uri);
      final titleNode = anchor.querySelector('.mtit');
      final countNode = titleNode?.querySelector('.mnum');
      final countText = _clean(countNode?.text ?? '');
      final title = _stripSuffix(_clean(titleNode?.text ?? ''), countText);
      if (fid == null || title.isEmpty) continue;
      result.add(
        ForumDirectoryForum(
          fid: fid,
          title: title,
          description: _clean(anchor.querySelector('.mtxt')?.text ?? ''),
          todayPosts: _count(countText),
        ),
      );
    }
    return result;
  }

  Uri? _resolve(String? source) {
    final value = source?.trim();
    if (value == null || value.isEmpty) return null;
    try {
      final uri = _resolver.resolve(value);
      return _resolver.isSameSite(uri) ? uri : null;
    } on FormatException {
      return null;
    }
  }

  String? _fid(Uri uri) {
    final query = uri.queryParameters['fid']?.trim();
    if (query != null && query.isNotEmpty) return query;
    return RegExp(r'forum-(\d+)-').firstMatch(uri.path)?.group(1);
  }

  void _validate(ForumDirectoryData data) {
    final sectionIds = <String>{};
    final forumIds = <String>{};
    for (final section in data.sections) {
      if (!sectionIds.add(section.identity)) {
        throw const FormatException('forum_directory_section_duplicated');
      }
      for (final forum in section.forums) {
        if (!forumIds.add(forum.fid)) {
          throw const FormatException('forum_directory_forum_duplicated');
        }
      }
    }
  }

  String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
  String _stripSuffix(String value, String suffix) =>
      suffix.isNotEmpty && value.endsWith(suffix)
      ? value.substring(0, value.length - suffix.length).trim()
      : value;
  int? _count(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }
}
