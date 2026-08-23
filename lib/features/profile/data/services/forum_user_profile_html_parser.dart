import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/profile/domain/models/forum_user_profile_models.dart';
import 'package:y300/features/profile/domain/models/profile_user_identity.dart';

final class ForumUserProfileHtmlParser {
  const ForumUserProfileHtmlParser();

  ForumUserProfileData parse({
    required String html,
    required String expectedUserId,
    required String siteOrigin,
  }) {
    final document = html_parser.parse(html);
    final root = document.querySelector('.userinfo');
    if (root == null) {
      throw const FormatException('User profile root is missing.');
    }
    final username = _cleanText(root.querySelector('h2.name')?.text ?? '');
    if (username.isEmpty) {
      throw const FormatException('User profile name is missing.');
    }

    final details = _parseDetails(root);
    final userIds = details
        .where((item) => item.label.toUpperCase() == 'UID')
        .map((item) => item.value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (userIds.length != 1 || userIds.single != expectedUserId.trim()) {
      throw const FormatException('User profile identity mismatch.');
    }

    final resolver = SiteUrlResolver(siteOrigin: siteOrigin);
    return ForumUserProfileData(
      identity: ProfileUserIdentity(
        userId: userIds.single,
        displayName: username,
      ),
      avatarUrl: _resolve(
        resolver,
        root.querySelector('.avatar_m img')?.attributes['src'],
      ),
      coverUrl: _parseCoverUrl(document, resolver),
      signatureHtml: _parseSignatureHtml(root),
      metrics: List<ForumUserProfileMetric>.unmodifiable(_parseMetrics(root)),
      details: List<ForumUserProfileDetail>.unmodifiable(details),
    );
  }

  List<ForumUserProfileMetric> _parseMetrics(html_dom.Element root) {
    return root
        .querySelectorAll('.user_box li')
        .map((item) {
          final valueNode = item.querySelector('span');
          final value = _cleanText(valueNode?.text ?? '');
          final label = _cleanText(item.text.replaceFirst(value, ''));
          if (label.isEmpty || value.isEmpty) {
            throw const FormatException('User profile metric is invalid.');
          }
          return ForumUserProfileMetric(label: label, value: value);
        })
        .toList(growable: false);
  }

  List<ForumUserProfileDetail> _parseDetails(html_dom.Element root) {
    html_dom.Element? detailSection;
    for (final section in root.querySelectorAll('.myinfo_list')) {
      if (section.querySelectorAll('li').any((item) {
        final value = item.querySelector('span');
        final label = _cleanText(
          item.nodes
              .takeWhile((node) => node != value)
              .map((node) => node.text)
              .join(),
        );
        return label.toUpperCase() == 'UID';
      })) {
        detailSection = section;
        break;
      }
    }
    if (detailSection == null) {
      throw const FormatException('User profile details are missing.');
    }

    final output = <ForumUserProfileDetail>[];
    for (final item in detailSection.querySelectorAll('li')) {
      if (item.querySelector('b') != null) {
        continue;
      }
      final valueNode = item.querySelector('span');
      final value = _cleanText(valueNode?.text ?? '');
      final label = _cleanText(
        item.nodes
            .takeWhile((node) => node != valueNode)
            .map((node) => node.text)
            .join(),
      );
      if (label.isEmpty || value.isEmpty) {
        throw const FormatException('User profile detail is invalid.');
      }
      output.add(ForumUserProfileDetail(label: label, value: value));
    }
    return output;
  }

  String? _parseSignatureHtml(html_dom.Element root) {
    final value = root.querySelector('.myinfo_list li.sig')?.innerHtml.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _parseCoverUrl(html_dom.Document document, SiteUrlResolver resolver) {
    for (final style in document.querySelectorAll('style')) {
      for (final rule in RegExp(
        r'([^{}]+)\{([^{}]*)\}',
      ).allMatches(style.text)) {
        final selectors = rule.group(1)!.split(',');
        final targetsUserAvatar = selectors.any(
          (selector) => RegExp(
            r'(^|[^\w-])\.user_avatar(?![\w-])',
            caseSensitive: false,
          ).hasMatch(selector),
        );
        if (!targetsUserAvatar) {
          continue;
        }
        final match = RegExp(
          r'background-image:\s*url\(([^)]+)\)',
          caseSensitive: false,
        ).firstMatch(rule.group(2)!);
        final raw = match
            ?.group(1)
            ?.trim()
            .replaceAll('"', '')
            .replaceAll("'", '');
        final resolved = _resolve(resolver, raw);
        if (resolved != null) {
          return resolved;
        }
      }
    }
    return null;
  }

  String? _resolve(SiteUrlResolver resolver, String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return resolver.resolve(raw);
  }

  String _cleanText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
