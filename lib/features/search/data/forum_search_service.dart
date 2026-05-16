import 'package:y300/features/search/data/models/discuz_search_models.dart';

class DiscuzSearchServiceException implements Exception {
  const DiscuzSearchServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DiscuzSearchResponse {
  const DiscuzSearchResponse({
    required this.items,
    required this.rateLimited,
    this.retryAfter = Duration.zero,
    this.nextPageUrl,
  });

  final List<DiscuzSearchResultItem> items;
  final bool rateLimited;
  final Duration retryAfter;
  final String? nextPageUrl;
}

abstract class ForumSearchService {
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  });

  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  });
}
