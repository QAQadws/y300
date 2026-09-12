import 'package:html/dom.dart';

import '../contracts/profile_and_blog.dart';
import '../contracts/user_blog_navigation.dart';
import 'discuz_blog_read_reference_parser.dart';

/// Separates the touch template's category prefixes from the escaped subject.
/// Unknown markup remains readable; only proven category links become actions.
final class DiscuzBlogHeadingParser {
  /// Uses the same source boundary as other native blog reading links.
  const DiscuzBlogHeadingParser(this.origin);

  /// Configured forum origin.
  final Uri origin;

  /// List labels contain no IDs and therefore cannot become native links.
  (String, List<String>) summary(Element? heading) {
    final copy = heading?.clone(true);
    final names = <String>[];
    if (copy != null) {
      for (final node in copy.nodes.toList()) {
        if (_ignorable(node)) continue;
        if (node is! Element || node.localName != 'span') break;
        final name = _bracketed(node.text);
        if (name == null || node.children.isNotEmpty) break;
        names.add(name);
        node.remove();
      }
    }
    return (_clean(copy?.text ?? ''), List.unmodifiable(names));
  }

  /// Detail category links must describe this author's category or a site feed.
  (String, List<UserBlogCategoryLink>) article(
    Element? heading, {
    required String ownerUserId,
  }) {
    final copy = heading?.clone(true);
    final links = <UserBlogCategoryLink>[];
    final seen = <UserBlogDirectoryQuery>{};
    if (copy != null) {
      for (final node in copy.nodes.toList()) {
        if (_ignorable(node)) continue;
        if (node is! Element || node.localName != 'em') break;
        final anchor = node.children.singleOrNull;
        final name = _bracketed(node.text);
        if (anchor?.localName != 'a' ||
            name == null ||
            _clean(anchor!.text) != name) {
          break;
        }
        final reference = DiscuzBlogReadReferenceParser(
          origin,
        ).resolve(anchor.attributes['href'] ?? '');
        if (reference is! UserBlogDirectoryReference) continue;
        final query = reference.query;
        final isCategory = switch (query.scope) {
          UserBlogFeedScope.public => query.categoryId != null,
          UserBlogFeedScope.self =>
            query.ownerUserId == ownerUserId &&
                query.personalCategoryId != null,
          UserBlogFeedScope.friends => false,
        };
        if (!isCategory) continue;
        if (seen.add(query)) {
          links.add(UserBlogCategoryLink(name: name, query: query));
        }
        node.remove();
      }
    }
    return (_clean(copy?.text ?? ''), List.unmodifiable(links));
  }

  bool _ignorable(Node node) =>
      node is Comment || (node is Text && node.text.trim().isEmpty);

  String? _bracketed(String text) {
    final value = _clean(text);
    if (!value.startsWith('[') || !value.endsWith(']')) return null;
    final name = value.substring(1, value.length - 1).trim();
    return name.isEmpty ? null : name;
  }

  String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
