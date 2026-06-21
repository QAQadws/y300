import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/profile/data/models/user_profile_models.dart';

class UserProfileHtmlParser {
  const UserProfileHtmlParser({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  UserProfileData parse(String html, {required String fallbackUid}) {
    final document = html_parser.parse(html);
    final details = _parseDetails(document);
    final uid =
        _detailValue(details, 'UID') ?? _extractUid(document) ?? fallbackUid;
    final username = _cleanText(
      document.querySelector('.userinfo h2.name')?.text ??
          document.querySelector('.header h2')?.text ??
          '',
    ).replaceFirst(RegExp(r'的资料$'), '');
    final title = _cleanText(document.querySelector('.header h2')?.text ?? '');
    final actions = _parseActions(document);

    return UserProfileData(
      uid: uid,
      username: username.isEmpty ? uid : username,
      title: title.isEmpty ? '${username.isEmpty ? uid : username}的资料' : title,
      avatarUrl: _resolve(
        document.querySelector('.avatar_m img')?.attributes['src'],
      ),
      coverUrl: _parseCoverUrl(document),
      signatureHtml: _parseSignatureHtml(document),
      threadUrl: _parseActionUrl(document, 'do=thread'),
      blogUrl: _parseActionUrl(document, 'do=blog'),
      messageUrl: _parseActionUrl(document, 'do=pm'),
      friendUrl:
          _parseActionUrl(document, 'ac=friend') ??
          _parseActionUrl(document, 'do=friend'),
      favoriteUrl: _parseActionUrl(document, 'do=favorite'),
      signUrl: _parseActionUrl(document, 'zqlj_sign'),
      settingsUrl: _parseSettingsUrl(document),
      logoutUrl: _parseLogoutUrl(document),
      actions: List<UserProfileAction>.unmodifiable(actions),
      credits: List<UserProfileMetric>.unmodifiable(_parseMetrics(document)),
      details: List<UserProfileDetailItem>.unmodifiable(details),
    );
  }

  List<UserProfileMetric> _parseMetrics(html_dom.Document document) {
    return document
        .querySelectorAll('.user_box li')
        .map((item) {
          final value = _cleanText(item.querySelector('span')?.text ?? '');
          final label = _cleanText(item.text.replaceFirst(value, ''));
          return UserProfileMetric(label: label, value: value);
        })
        .where((metric) => metric.label.isNotEmpty || metric.value.isNotEmpty)
        .toList(growable: false);
  }

  String? _parseSignatureHtml(html_dom.Document document) {
    final signatureNode = document.querySelector('.myinfo_list li.sig');
    final html = signatureNode?.innerHtml.trim();
    return html == null || html.isEmpty ? null : html;
  }

  List<UserProfileDetailItem> _parseDetails(html_dom.Document document) {
    html_dom.Element? detailSection;
    for (final section in document.querySelectorAll('.myinfo_list')) {
      if (_cleanText(section.querySelector('li b')?.text ?? '') == '个人资料') {
        detailSection = section;
        break;
      }
    }
    if (detailSection == null) {
      return const <UserProfileDetailItem>[];
    }
    final output = <UserProfileDetailItem>[];
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
      if (label.isEmpty && value.isEmpty) {
        continue;
      }
      output.add(UserProfileDetailItem(label: label, value: value));
    }
    return output;
  }

  String? _detailValue(List<UserProfileDetailItem> details, String label) {
    for (final detail in details) {
      if (detail.label == label && detail.value.isNotEmpty) {
        return detail.value;
      }
    }
    return null;
  }

  String? _parseActionUrl(html_dom.Document document, String queryNeedle) {
    return _resolve(
      document
          .querySelector('.myinfo_list_ico a[href*="$queryNeedle"]')
          ?.attributes['href'],
    );
  }

  List<UserProfileAction> _parseActions(html_dom.Document document) {
    final actions = <UserProfileAction>[];
    for (final anchor in document.querySelectorAll('.myinfo_list_ico a')) {
      final label = _cleanText(anchor.text);
      final url = _resolve(anchor.attributes['href']);
      if (label.isEmpty || url == null) {
        continue;
      }
      actions.add(UserProfileAction(label: label, url: url));
    }
    return actions;
  }

  String? _parseSettingsUrl(html_dom.Document document) {
    return _resolve(
      document
          .querySelector('.myinfo_list li b + span a[href*="spacecp"]')
          ?.attributes['href'],
    );
  }

  String? _parseLogoutUrl(html_dom.Document document) {
    return _resolve(document.querySelector('.btn_exit a')?.attributes['href']);
  }

  String? _parseCoverUrl(html_dom.Document document) {
    final styles = document.querySelectorAll('style');
    for (final style in styles) {
      final match = RegExp(
        r'background-image:\s*url\(([^)]+)\)',
        caseSensitive: false,
      ).firstMatch(style.text);
      final url = match
          ?.group(1)
          ?.trim()
          .replaceAll('"', '')
          .replaceAll("'", '');
      final resolved = _resolve(url);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  String? _extractUid(html_dom.Document document) {
    for (final anchor in document.querySelectorAll('a[href*="uid="]')) {
      final url = _resolve(anchor.attributes['href']);
      if (url == null) {
        continue;
      }
      final uid = Uri.tryParse(url)?.queryParameters['uid'];
      if (uid != null && uid.isNotEmpty) {
        return uid;
      }
    }
    return null;
  }

  String? _resolve(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return _urlResolver.resolve(raw);
  }

  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
