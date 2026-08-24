import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../contracts/forum_directory.dart';
import '../contracts/forum_home.dart';
import '../url/forum_uri_resolver.dart';

final class ForumHomeHtmlParser {
  ForumHomeHtmlParser({required Uri siteOrigin})
    : _resolver = ForumUriResolver(siteOrigin: siteOrigin);

  final ForumUriResolver _resolver;

  ForumHomeDocument parse(String source) {
    final document = html_parser.parse(source);
    final forumList = document.querySelector('.forumlist');
    if (forumList == null) {
      throw const FormatException('forum_home_directory_missing');
    }
    final regular = <ForumDirectorySection>[];
    final favorites = <ForumHomeFavoriteForum>[];
    final sectionIds = <String>{};
    final forumIds = <String>{};
    for (final header in forumList.querySelectorAll('.subforumshow')) {
      final section = _target(forumList, header.attributes['href']);
      if (section == null) continue;
      final identity = _sectionIdentity(header, section);
      final title = _clean(header.querySelector('h2')?.text ?? header.text);
      final items = _forums(section);
      if (identity.isEmpty || title.isEmpty || items.isEmpty) continue;
      if (!sectionIds.add(identity)) {
        throw const FormatException('forum_home_section_duplicated');
      }
      if (section.id == 'sub-forum-myfav') {
        favorites.addAll(
          items.map(
            (item) => ForumHomeFavoriteForum(
              fid: item.fid,
              title: item.title,
              description: item.description,
              todayPosts: item.todayPosts,
            ),
          ),
        );
        continue;
      }
      for (final item in items) {
        if (!forumIds.add(item.fid)) {
          throw const FormatException('forum_home_forum_duplicated');
        }
      }
      regular.add(
        ForumDirectorySection(
          identity: identity,
          title: title,
          forums: List.unmodifiable(items),
        ),
      );
    }
    return ForumHomeDocument(
      directory: ForumDirectoryData(sections: List.unmodifiable(regular)),
      carousel: List.unmodifiable(_carousel(document)),
      favoriteForums: List.unmodifiable(favorites),
    );
  }

  List<ForumHomeCarouselReference> _carousel(html_dom.Document document) {
    final root =
        document.querySelector('#forum > div.index-top-wrapper') ??
        document.querySelector('#forum .index-top-wrapper') ??
        document.querySelector('.index-top-wrapper') ??
        document;
    final result = <ForumHomeCarouselReference>[];
    final identities = <String>{};
    for (final slide in root.querySelectorAll('.yami-swiper .swiper-slide')) {
      final anchor = slide.querySelector('a');
      final image = anchor?.querySelector('img');
      final target = _resolve(anchor?.attributes['href'], sameSite: false);
      final imageUri = _resolve(image?.attributes['src'], sameSite: false);
      if (target == null || imageUri == null) continue;
      final identity = '${imageUri.toString()}|${target.toString()}';
      if (!identities.add(identity)) continue;
      result.add(
        ForumHomeCarouselReference(imageUri: imageUri, targetUri: target),
      );
    }
    return result;
  }

  List<ForumDirectoryForum> _forums(html_dom.Element section) {
    final result = <ForumDirectoryForum>[];
    final ids = <String>{};
    for (final anchor in section.querySelectorAll('a.murl')) {
      final uri = _resolve(anchor.attributes['href'], sameSite: true);
      final fid = uri == null ? null : _fid(uri);
      final titleNode = anchor.querySelector('.mtit');
      final countText = _clean(titleNode?.querySelector('.mnum')?.text ?? '');
      final title = _stripSuffix(_clean(titleNode?.text ?? ''), countText);
      if (fid == null || title.isEmpty || !ids.add(fid)) continue;
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

  html_dom.Element? _target(html_dom.Element root, String? selector) {
    final value = selector?.trim() ?? '';
    if (value.isEmpty) return null;
    try {
      return root.querySelector(value);
    } catch (_) {
      return null;
    }
  }

  String _sectionIdentity(html_dom.Element header, html_dom.Element section) {
    final target = header.attributes['href']?.trim() ?? '';
    return target.startsWith('#') && target.length > 1
        ? target.substring(1)
        : section.id.trim();
  }

  Uri? _resolve(String? value, {required bool sameSite}) {
    final source = value?.trim() ?? '';
    if (source.isEmpty) return null;
    try {
      final uri = _resolver.resolve(source);
      if (!const {'http', 'https'}.contains(uri.scheme)) return null;
      return !sameSite || _resolver.isSameSite(uri) ? uri : null;
    } on FormatException {
      return null;
    }
  }

  String? _fid(Uri uri) => uri.queryParameters['fid']?.trim().isNotEmpty == true
      ? uri.queryParameters['fid']!.trim()
      : RegExp(r'forum-(\d+)-').firstMatch(uri.path)?.group(1);
  String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
  String _stripSuffix(String value, String suffix) =>
      suffix.isNotEmpty && value.endsWith(suffix)
      ? value.substring(0, value.length - suffix.length).trim()
      : value;
  int? _count(String value) =>
      int.tryParse(RegExp(r'\d+').firstMatch(value)?.group(0) ?? '');
}
