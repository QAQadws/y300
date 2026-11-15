// ignore_for_file: public_member_api_docs

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../contracts/forum_directory.dart';
import '../contracts/forum_home.dart';
import '../url/forum_uri_resolver.dart';

final class ForumHomeHtmlParser {
  ForumHomeHtmlParser({required Uri siteOrigin})
    : _resolver = ForumUriResolver(siteOrigin: siteOrigin);

  final ForumUriResolver _resolver;

  ForumHomeDocument parse(String source) =>
      parseDocument(html_parser.parse(source));

  ForumHomeDocument parseDocument(html_dom.Document document) {
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
    void appendAnchor(html_dom.Element? anchor, {bool standalone = false}) {
      final image = anchor?.querySelector('img');
      final rawTarget = anchor?.attributes['href']?.trim();
      final target = _resolve(rawTarget, sameSite: false);
      final imageUri = _resolve(image?.attributes['src'], sameSite: false);
      if (target == null || imageUri == null) return;
      if (standalone &&
          (rawTarget?.startsWith('#') == true || _isNavigationTarget(target))) {
        return;
      }
      final identity = '${imageUri.toString()}|${target.toString()}';
      if (!identities.add(identity)) return;
      result.add(
        ForumHomeCarouselReference(imageUri: imageUri, targetUri: target),
      );
    }

    for (final slide in root.querySelectorAll('.yami-swiper .swiper-slide')) {
      appendAnchor(slide.querySelector('a'));
    }
    // Standalone campaigns are identified by page position and structure,
    // independently of where their images were uploaded. Append them so the
    // existing first slide continues to determine the shared carousel ratio.
    for (final anchor in _standaloneBannerAnchors(document)) {
      appendAnchor(anchor, standalone: true);
    }
    return result;
  }

  Iterable<html_dom.Element> _standaloneBannerAnchors(
    html_dom.Document document,
  ) sync* {
    final forum = document.querySelector('#forum');
    if (forum == null) return;
    for (final container in forum.children) {
      // Never collect banners from the directory, content below it or footer.
      if (container.classes.contains('forumlist') ||
          container.querySelector('.forumlist') != null) {
        break;
      }
      final classes = container.classes;
      if (!(classes.contains('home-campaign-banner') ||
              (classes.contains('wp') && classes.contains('cl'))) ||
          container.attributes.containsKey('hidden') ||
          const {'header', 'footer', 'nav'}.contains(container.localName) ||
          classes.any(
            const {'header', 'footer', 'foot', 'nav', 'float-menu'}.contains,
          ) ||
          _clean(container.text).isNotEmpty) {
        continue;
      }
      // Direct image-only links distinguish a banner strip from arbitrary
      // nested widgets, captions and navigation. Comments/whitespace are fine.
      final anchors = container.children;
      if (anchors.isNotEmpty && anchors.every(_isImageLink)) {
        for (final anchor in anchors) {
          if (!anchor.attributes.containsKey('hidden') &&
              !anchor.children.single.attributes.containsKey('hidden')) {
            yield anchor;
          }
        }
      }
    }
  }

  bool _isImageLink(html_dom.Element anchor) =>
      anchor.localName == 'a' &&
      anchor.children.length == 1 &&
      anchor.children.single.localName == 'img';

  bool _isNavigationTarget(Uri target) {
    if (!_resolver.isSameSite(target)) return false;
    return switch (target.path) {
      '' || '/' || '/index.php' || '/search.php' || '/member.php' => true,
      '/forum.php' => const {
        null,
        '',
        'index',
      }.contains(target.queryParameters['mod']),
      _ => false,
    };
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
