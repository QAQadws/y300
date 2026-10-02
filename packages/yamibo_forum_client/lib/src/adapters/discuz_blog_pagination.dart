import 'package:html/dom.dart';

import '../contracts/data_read_contract.dart';
import '../contracts/profile_and_blog.dart';
import '../url/forum_uri_resolver.dart';

/// Validates pagination against the requested feed or article identity.
final class DiscuzBlogPagination {
  /// Creates a parser scoped to one site.
  const DiscuzBlogPagination(this.siteOrigin);

  /// The configured forum origin.
  final Uri siteOrigin;

  /// Parses the shared Discuz mobile pager without deriving pages from counts.
  (UserBlogPagination, PaginationPrecision) parse(
    Document document, {
    required int requestedPage,
    required bool Function(Uri) matchesContext,
    bool lastPage = false,
    bool singleComment = false,
  }) {
    final container = document.querySelector('.pg');
    if (singleComment) {
      // A cid query returns a filtered row but may retain the full article pager.
      return (
        const UserBlogPagination(
          currentPage: 1,
          hasPrevious: false,
          hasNext: false,
        ),
        PaginationPrecision.directional,
      );
    }
    if (container == null) {
      if (requestedPage != 1) {
        throw const FormatException('blog_page_unverified');
      }
      return (
        const UserBlogPagination(
          currentPage: 1,
          totalPages: 1,
          hasPrevious: false,
          hasNext: false,
        ),
        PaginationPrecision.exact,
      );
    }
    final current = int.tryParse(
      container.querySelector('strong')?.text.trim() ?? '',
    );
    final totalText = container.querySelector('label span')?.text;
    final totalMatch = totalText == null
        ? null
        : RegExp(r'^\s*/\s*(\d+)\s+\S+\s*$').firstMatch(totalText);
    final total = int.tryParse(totalMatch?.group(1) ?? '');
    if (current == null ||
        current < 1 ||
        (!lastPage && current != requestedPage) ||
        (totalText != null && (total == null || total < current))) {
      throw const FormatException('blog_page_identity_mismatch');
    }
    final resolver = ForumUriResolver(siteOrigin: siteOrigin);
    for (final anchor in container.querySelectorAll('a[href]')) {
      final uri = resolver.resolve(anchor.attributes['href']!);
      final target = int.tryParse(uri.queryParameters['page'] ?? '1');
      if (!resolver.isSameSite(uri) ||
          !matchesContext(uri) ||
          target == null ||
          target < 1 ||
          (total != null && target > total) ||
          (anchor.classes.contains('prev') && target != current - 1) ||
          (anchor.classes.contains('nxt') && target != current + 1)) {
        throw const FormatException('blog_pagination_link_invalid');
      }
    }
    final previous = container.querySelector('a.prev') != null;
    final next = container.querySelector('a.nxt') != null;
    if ((lastPage && next) ||
        (total != null &&
            (previous != (current > 1) || next != (current < total)))) {
      throw const FormatException('blog_pagination_inconsistent');
    }
    return (
      UserBlogPagination(
        currentPage: current,
        totalPages: total,
        hasPrevious: previous,
        hasNext: next,
      ),
      total == null
          ? PaginationPrecision.directional
          : PaginationPrecision.exact,
    );
  }
}
