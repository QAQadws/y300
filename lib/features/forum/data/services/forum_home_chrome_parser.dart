import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';

class ForumHomeChromeParser {
  const ForumHomeChromeParser({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  ForumHomeChromeData parse(String html) {
    final document = html_parser.parse(html);
    final topWrapper =
        document.querySelector('#forum > div.index-top-wrapper') ??
        document.querySelector('#forum .index-top-wrapper') ??
        document.querySelector('.index-top-wrapper') ??
        document;
    final slides = topWrapper.querySelectorAll('.yami-swiper .swiper-slide');
    final items = <ForumHomeCarouselItem>[];
    for (final slide in slides) {
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
    return ForumHomeChromeData(
      carouselItems: List<ForumHomeCarouselItem>.unmodifiable(items),
      favoriteForums: List<ForumHomeChromeForumItem>.unmodifiable(
        _parseFavoriteForums(document),
      ),
    );
  }

  List<ForumHomeChromeForumItem> _parseFavoriteForums(
    html_dom.Document document,
  ) {
    final favoriteSection = document.querySelector('#sub-forum-myfav');
    if (favoriteSection == null) {
      return const <ForumHomeChromeForumItem>[];
    }
    final output = <ForumHomeChromeForumItem>[];
    for (final anchor in favoriteSection.querySelectorAll('a.murl')) {
      final fid = _extractFid(anchor.attributes['href']);
      if (fid == null || fid.isEmpty) {
        continue;
      }
      final titleNode = anchor.querySelector('.mtit');
      final countNode = titleNode?.querySelector('.mnum');
      final title = _stripSuffixText(
        titleNode?.text.trim() ?? '',
        countNode?.text.trim() ?? '',
      );
      final description = anchor.querySelector('.mtxt')?.text.trim() ?? '';
      output.add(
        ForumHomeChromeForumItem(
          fid: fid,
          title: title,
          description: description,
          todayPosts: _parseTodayPosts(countNode?.text),
        ),
      );
    }
    return output;
  }

  String? _resolve(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return _urlResolver.resolve(value);
  }

  String? _extractFid(String? raw) {
    final resolved = raw == null ? null : _resolve(raw);
    final uri = resolved == null ? null : Uri.tryParse(resolved);
    final queryFid = uri?.queryParameters['fid']?.trim();
    if (queryFid != null && queryFid.isNotEmpty) {
      return queryFid;
    }
    final path = uri?.path ?? '';
    final forumMatch = RegExp(r'forum-(\d+)-').firstMatch(path);
    return forumMatch?.group(1);
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
