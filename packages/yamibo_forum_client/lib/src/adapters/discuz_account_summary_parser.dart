// ignore_for_file: public_member_api_docs

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../contracts/profile_and_blog.dart';
import 'discuz_profile_html_parsers.dart';

/// Parses only the desktop profile projection needed by the account header.
final class DiscuzAccountSummaryParser {
  const DiscuzAccountSummaryParser({required this.siteOrigin});

  final Uri siteOrigin;

  bool isExpectedUri(Uri uri, String userId) =>
      _sameOrigin(uri) &&
      uri.path == '/home.php' &&
      _queryMatches(uri, {'mod': 'space', 'uid': userId, 'do': 'profile'});

  CurrentUserProfileData parse(String source, String userId) {
    final document = html.parse(source);
    final assignmentCount = document
        .querySelectorAll('script')
        .fold<int>(
          0,
          (count, script) =>
              count +
              RegExp(
                r'(?:^|[,;\s])discuz_uid\s*=',
              ).allMatches(script.text).length,
        );
    final identities = document
        .querySelectorAll('script')
        .expand(
          (script) => RegExp(
            r'''(?:^|[,;\s])discuz_uid\s*=\s*(['"])(\d+)\1''',
          ).allMatches(script.text),
        )
        .toList();
    if (assignmentCount != 1 || identities.length != 1) {
      throw const FormatException('account_session_identity_invalid');
    }
    final viewer = identities.single.group(2);
    if (viewer == '0') throw const ForumUserProfileUnauthorized();
    if (viewer != userId) {
      throw const FormatException('account_session_identity_mismatch');
    }
    final roots = document.querySelectorAll('.u_profile');
    if (roots.length != 1) {
      throw const FormatException('account_desktop_profile_missing');
    }
    final root = roots.single;
    final uidNodes = root.querySelectorAll('h2 > span.xw0');
    if (uidNodes.length != 1 ||
        _clean(uidNodes.single.text) != '(UID: $userId)') {
      throw const FormatException('account_profile_identity_mismatch');
    }
    final heading = uidNodes.single.parent!;
    final nameNode = heading.clone(true);
    nameNode.querySelector('span.xw0')!.remove();
    final name = _clean(nameNode.text);
    if (name.isEmpty) throw const FormatException('account_name_missing');

    final counts = _counts(heading.parent!, userId);
    final group = _group(root);
    final credits = _credits(root);
    if (credits != null && group.credits != null && credits != group.credits) {
      throw const FormatException('account_credit_total_conflict');
    }
    return CurrentUserProfileData(
      identity: ProfileUserIdentity(userId: userId, displayName: name),
      avatarUrl: _avatar(document, userId),
      groupId: group.id,
      groupName: group.name,
      creditTotal: credits,
      threadCount: counts['thread'],
      // The desktop template already subtracts threads from total posts.
      replyCount: counts['reply'],
    );
  }

  Map<String, int> _counts(Element section, String userId) {
    final lists = section.children.where(
      (node) => node.localName == 'ul' && node.classes.contains('bbda'),
    );
    if (lists.length > 1) {
      throw const FormatException('account_statistics_repeated');
    }
    final counts = <String, int>{};
    if (lists.isEmpty) return counts;
    for (final link in lists.single.querySelectorAll('a[href]')) {
      final uri = siteOrigin.resolve(link.attributes['href']!);
      final types = uri.queryParametersAll['type'] ?? const <String>[];
      if (!types.any((type) => type == 'thread' || type == 'reply')) continue;
      final type = types.first;
      if (!_sameOrigin(uri) ||
          uri.path != '/home.php' ||
          !_queryMatches(uri, {
            'mod': 'space',
            'uid': userId,
            'do': 'thread',
            'view': 'me',
            'type': type,
            'from': 'space',
          }) ||
          counts.containsKey(type)) {
        throw const FormatException('account_statistics_link_invalid');
      }
      final pattern = type == 'thread'
          ? RegExp(r'^(?:主题数|主題數)\s+(\d+)$')
          : RegExp(r'^(?:回帖数|回帖數|回覆數)\s+(\d+)$');
      final value = pattern.firstMatch(_clean(link.text))?.group(1);
      final count = value == null ? null : int.tryParse(value);
      if (count == null || count < 0) {
        throw const FormatException('account_statistics_value_invalid');
      }
      counts[type] = count;
    }
    return counts;
  }

  ({String? id, String? name, int? credits}) _group(Element root) {
    final rows = root.querySelectorAll('li').where((node) {
      final label = node.children.firstOrNull;
      return label?.localName == 'em' &&
          const {'用户组', '用戶組', '使用者群組'}.contains(_clean(label!.text));
    }).toList();
    if (rows.isEmpty) return (id: null, name: null, credits: null);
    if (rows.length != 1) {
      throw const FormatException('account_group_repeated');
    }
    final row = rows.single;
    final links = row.querySelectorAll('a[href]');
    if (links.isEmpty) return (id: null, name: null, credits: null);
    if (links.length != 1) {
      throw const FormatException('account_group_link_repeated');
    }
    final link = links.single;
    final uri = siteOrigin.resolve(link.attributes['href']!);
    final id = uri.queryParameters['gid'];
    if (!_sameOrigin(uri) ||
        uri.path != '/home.php' ||
        id == null ||
        !RegExp(r'^[1-9]\d*$').hasMatch(id) ||
        !_queryMatches(uri, {'mod': 'spacecp', 'ac': 'usergroup', 'gid': id})) {
      throw const FormatException('account_group_link_invalid');
    }
    int? credits;
    final tips = row.querySelectorAll('[tip]');
    if (tips.length > 1) {
      throw const FormatException('account_group_tip_repeated');
    }
    if (tips.isNotEmpty) {
      final raw = tips.single.attributes['tip']!;
      final match = RegExp(r'^(?:积分|積分)\s+(-?\d+)\s*[,，]').firstMatch(raw);
      credits = match == null ? null : int.tryParse(match.group(1)!);
      if (credits == null) {
        throw const FormatException('account_group_tip_invalid');
      }
    }
    final name = _clean(link.text);
    return (id: id, name: name.isEmpty ? null : name, credits: credits);
  }

  int? _credits(Element root) {
    final sections = root.querySelectorAll('#psts');
    if (sections.isEmpty) return null;
    if (sections.length != 1) {
      throw const FormatException('account_credits_section_repeated');
    }
    final lists = sections.single.children.where(
      (node) => node.localName == 'ul' && node.classes.contains('pf_l'),
    );
    if (lists.isEmpty) return null;
    if (lists.length != 1) {
      throw const FormatException('account_credits_repeated');
    }
    // Discuz renders the total before its extcredits loop, whose labels may
    // also be "积分". Never overwrite the first row or skip a malformed total.
    for (final row in lists.single.children) {
      final label = row.children.firstOrNull;
      if (row.localName != 'li' ||
          label?.localName != 'em' ||
          !const {'积分', '積分'}.contains(_clean(label!.text))) {
        continue;
      }
      final valueNode = row.clone(true);
      valueNode.children.first.remove();
      final value = _clean(valueNode.text);
      final credits = RegExp(r'^-?\d+$').hasMatch(value)
          ? int.tryParse(value)
          : null;
      if (credits == null) {
        throw const FormatException('account_credits_invalid');
      }
      return credits;
    }
    return null;
  }

  String? _avatar(Document document, String userId) {
    final cards = document.querySelectorAll('#pcd');
    if (cards.isEmpty) return null;
    if (cards.length != 1) {
      throw const FormatException('account_avatar_repeated');
    }
    final images = cards.single.querySelectorAll('.hm a.avtm img');
    if (images.isEmpty) return null;
    if (images.length != 1) {
      throw const FormatException('account_avatar_repeated');
    }
    final image = images.single;
    final link = siteOrigin.resolve(image.parent!.attributes['href'] ?? '');
    if (!_sameOrigin(link) ||
        !((link.path == '/space-uid-$userId.html' && !link.hasQuery) ||
            (link.path == '/home.php' &&
                _queryMatches(link, {'mod': 'space', 'uid': userId})))) {
      throw const FormatException('account_avatar_identity_mismatch');
    }
    final src = image.attributes['src']?.trim();
    if (src == null || src.isEmpty) return null;
    final uri = siteOrigin.resolve(src);
    return _sameOrigin(uri) ? uri.toString() : null;
  }

  bool _sameOrigin(Uri uri) =>
      uri.scheme == siteOrigin.scheme &&
      uri.host == siteOrigin.host &&
      uri.port == siteOrigin.port &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment;

  bool _queryMatches(Uri uri, Map<String, String> expected) {
    final values = uri.queryParametersAll;
    return values.length == expected.length &&
        expected.entries.every((entry) {
          final items = values[entry.key];
          return items?.length == 1 && items!.single == entry.value;
        });
  }

  String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
