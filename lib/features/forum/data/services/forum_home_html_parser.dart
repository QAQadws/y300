import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/data/models/forum_home_html_models.dart';

class ForumHomeHtmlParser {
  const ForumHomeHtmlParser({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  ForumHomeHtmlData parse(String html) {
    final document = html_parser.parse(html);
    return ForumHomeHtmlData(
      carouselItems: List<ForumHomeCarouselItem>.unmodifiable(
        _parseCarouselItems(document),
      ),
      sections: List<ForumHomeHtmlSection>.unmodifiable(
        _parseSections(document),
      ),
    );
  }

  List<ForumHomeCarouselItem> _parseCarouselItems(html_dom.Document document) {
    final topWrapper =
        document.querySelector('#forum > div.index-top-wrapper') ??
        document.querySelector('#forum .index-top-wrapper') ??
        document.querySelector('.index-top-wrapper') ??
        document;
    final items = <ForumHomeCarouselItem>[];
    for (final slide in topWrapper.querySelectorAll(
      '.yami-swiper .swiper-slide',
    )) {
      final anchor = slide.querySelector('a');
      final image = anchor?.querySelector('img');
      final targetUrl = _resolve(anchor?.attributes['href']);
      final imageUrl = _resolve(image?.attributes['src']);
      if (targetUrl == null || imageUrl == null) {
        continue;
      }
      items.add(
        ForumHomeCarouselItem(imageUrl: imageUrl, targetUrl: targetUrl),
      );
    }
    return items;
  }

  List<ForumHomeHtmlSection> _parseSections(html_dom.Document document) {
    final forumList = document.querySelector('.forumlist');
    if (forumList == null) {
      return const <ForumHomeHtmlSection>[];
    }

    final sections = <ForumHomeHtmlSection>[];
    for (final header in forumList.querySelectorAll('.subforumshow')) {
      final targetSelector = header.attributes['href']?.trim();
      final sectionElement = _querySelectorSafely(forumList, targetSelector);
      if (sectionElement == null) {
        continue;
      }

      final items = _parseSectionItems(sectionElement);
      if (items.isEmpty) {
        continue;
      }

      final title = _cleanText(header.querySelector('h2')?.text ?? header.text);
      if (title.isEmpty) {
        continue;
      }
      sections.add(
        ForumHomeHtmlSection(
          title: title,
          items: List<ForumHomeHtmlForumItem>.unmodifiable(items),
          isFavoriteSection: _isFavoriteSection(sectionElement),
          isInitiallyCollapsed: _isInitiallyCollapsed(sectionElement),
        ),
      );
    }
    return sections;
  }

  html_dom.Element? _querySelectorSafely(
    html_dom.Element root,
    String? selector,
  ) {
    if (selector == null || selector.isEmpty) {
      return null;
    }
    try {
      return root.querySelector(selector);
    } catch (_) {
      return null;
    }
  }

  List<ForumHomeHtmlForumItem> _parseSectionItems(html_dom.Element section) {
    final output = <ForumHomeHtmlForumItem>[];
    final seen = <String>{};
    for (final anchor in section.querySelectorAll('a.murl')) {
      final listItem = anchor.parent;
      final url = _resolve(anchor.attributes['href']);
      final fid = _extractFid(url);
      if (url == null || fid == null || fid.isEmpty || !seen.add(fid)) {
        continue;
      }

      final titleNode = anchor.querySelector('.mtit');
      final countNode = titleNode?.querySelector('.mnum');
      final title = _stripSuffixText(
        _cleanText(titleNode?.text ?? ''),
        _cleanText(countNode?.text ?? ''),
      );
      if (title.isEmpty) {
        continue;
      }

      output.add(
        ForumHomeHtmlForumItem(
          fid: fid,
          title: title,
          description: _cleanText(anchor.querySelector('.mtxt')?.text ?? ''),
          todayPosts: _parseTodayPosts(countNode?.text),
          url: url,
          iconUrl: _resolve(listItem?.querySelector('img')?.attributes['src']),
        ),
      );
    }
    return output;
  }

  bool _isFavoriteSection(html_dom.Element section) {
    return section.id == 'sub-forum-myfav';
  }

  bool _isInitiallyCollapsed(html_dom.Element section) {
    final style = section.attributes['style']?.toLowerCase() ?? '';
    return style.contains('display') && style.contains('none');
  }

  String? _resolve(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return _urlResolver.resolve(value);
  }

  String? _extractFid(String? resolvedUrl) {
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(resolvedUrl);
    final queryFid = uri?.queryParameters['fid']?.trim();
    if (queryFid != null && queryFid.isNotEmpty) {
      return queryFid;
    }
    final path = uri?.path ?? '';
    final forumMatch = RegExp(r'forum-(\d+)-').firstMatch(path);
    return forumMatch?.group(1);
  }

  String _cleanText(String source) {
    return source.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _stripSuffixText(String source, String suffix) {
    if (suffix.isEmpty || !source.endsWith(suffix)) {
      return source.trim();
    }
    return source.substring(0, source.length - suffix.length).trim();
  }

  int? _parseTodayPosts(String? source) {
    if (source == null || source.trim().isEmpty) {
      return null;
    }
    final match = RegExp(r'\d+').firstMatch(source);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(0) ?? '');
  }
}
