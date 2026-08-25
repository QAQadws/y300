import '../contracts/forum_search.dart';
import '../url/forum_uri_resolver.dart';

enum DiscuzSearchContextFailure {
  invalidUri,
  invalidSearchId,
  invalidPage,
  scopeMismatch,
}

final class DiscuzSearchPageContext {
  const DiscuzSearchPageContext({required this.searchId, required this.page});

  final String searchId;
  final int page;
}

final class DiscuzSearchContextValidation {
  const DiscuzSearchContextValidation.success(this.context) : failure = null;

  const DiscuzSearchContextValidation.failure(this.failure) : context = null;

  final DiscuzSearchPageContext? context;
  final DiscuzSearchContextFailure? failure;
}

/// Validates the opaque result context created by a Discuz search POST.
///
/// Discuz may canonicalize a scoped `mod=curforum&srhfid=...` submission to a
/// `mod=forum&searchid=...` result URI. The server-owned search ID preserves
/// the submitted scope, so an omitted result `srhfid` is valid; an explicitly
/// conflicting forum ID remains invalid.
final class DiscuzSearchContextValidator {
  DiscuzSearchContextValidator({required this.siteOrigin})
    : _resolver = ForumUriResolver(siteOrigin: siteOrigin);

  final Uri siteOrigin;
  final ForumUriResolver _resolver;

  DiscuzSearchContextValidation validate(
    Uri uri, {
    required ForumSearchQuery query,
    required int expectedPage,
    String? expectedSearchId,
    bool allowImplicitFirstPage = false,
  }) {
    if (!_isAllowedSearchUri(uri)) {
      return const DiscuzSearchContextValidation.failure(
        DiscuzSearchContextFailure.invalidUri,
      );
    }

    final searchIds = uri.queryParametersAll['searchid'] ?? const <String>[];
    final searchId = searchIds.length == 1 ? searchIds.single.trim() : '';
    if (searchId.isEmpty ||
        (expectedSearchId != null && searchId != expectedSearchId)) {
      return const DiscuzSearchContextValidation.failure(
        DiscuzSearchContextFailure.invalidSearchId,
      );
    }

    final pages = uri.queryParametersAll['page'] ?? const <String>[];
    final page = pages.isEmpty && allowImplicitFirstPage && expectedPage == 1
        ? 1
        : pages.length == 1
        ? int.tryParse(pages.single.trim())
        : null;
    if (page != expectedPage) {
      return const DiscuzSearchContextValidation.failure(
        DiscuzSearchContextFailure.invalidPage,
      );
    }

    if (!_matchesScope(uri, query.normalized())) {
      return const DiscuzSearchContextValidation.failure(
        DiscuzSearchContextFailure.scopeMismatch,
      );
    }
    return DiscuzSearchContextValidation.success(
      DiscuzSearchPageContext(searchId: searchId, page: page!),
    );
  }

  bool _isAllowedSearchUri(Uri uri) {
    if (!_resolver.isSameSite(uri) ||
        uri.path.toLowerCase() != '/search.php' ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    final originScheme = siteOrigin.scheme.toLowerCase();
    return uri.scheme.toLowerCase() == originScheme &&
        uri.port == siteOrigin.port;
  }

  bool _matchesScope(Uri uri, ForumSearchQuery query) {
    final mods = uri.queryParametersAll['mod'] ?? const <String>[];
    final forumIds = uri.queryParametersAll['srhfid'] ?? const <String>[];
    if (mods.length != 1 || forumIds.length > 1) return false;
    final mod = mods.single.trim().toLowerCase();
    return switch (query.scope) {
      ForumSearchScope.allForums => mod == 'forum' && forumIds.isEmpty,
      ForumSearchScope.currentForum =>
        (mod == 'curforum' || mod == 'forum') &&
            (forumIds.isEmpty ||
                forumIds.single.trim() == query.normalizedForumId),
    };
  }
}
