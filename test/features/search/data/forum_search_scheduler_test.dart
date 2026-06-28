import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/search/data/services/forum_search_scheduler.dart';
import 'package:y300/features/search/data/services/forum_search_service.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';

void main() {
  group('ForumSearchScheduler', () {
    test('serializes scheduled searches with at least 10.5 seconds between starts', () async {
      var now = DateTime(2026, 5, 16, 12, 0, 0);
      final delays = <Duration>[];
      final raw = _RecordingForumSearchService(nowProvider: () => now);
      final scheduler = ForumSearchScheduler(
        rawService: raw,
        nowProvider: () => now,
        delay: (duration) async {
          delays.add(duration);
          now = now.add(duration);
        },
      );

      final first = scheduler.searchForum(keyword: 'alpha');
      final second = scheduler.searchForum(keyword: 'beta');
      await Future.wait(<Future<DiscuzSearchResponse>>[first, second]);

      expect(raw.startedKeywords, <String>['alpha', 'beta']);
      expect(raw.startedAt[1].difference(raw.startedAt[0]), ForumSearchScheduler.defaultInterval);
      expect(delays, <Duration>[ForumSearchScheduler.defaultInterval]);
    });

    test('bypasses scheduler when enforceRateLimit is false', () async {
      var now = DateTime(2026, 5, 16, 12, 0, 0);
      final delays = <Duration>[];
      final raw = _RecordingForumSearchService(nowProvider: () => now);
      final scheduler = ForumSearchScheduler(
        rawService: raw,
        nowProvider: () => now,
        delay: (duration) async {
          delays.add(duration);
          now = now.add(duration);
        },
      );

      await scheduler.searchForum(keyword: 'alpha', enforceRateLimit: false);
      await scheduler.searchForum(keyword: 'beta', enforceRateLimit: false);

      expect(raw.startedKeywords, <String>['alpha', 'beta']);
      expect(delays, isEmpty);
    });
  });
}

class _RecordingForumSearchService implements ForumSearchService {
  _RecordingForumSearchService({required DateTime Function() nowProvider})
      : _nowProvider = nowProvider;

  final DateTime Function() _nowProvider;
  final List<String> startedKeywords = <String>[];
  final List<DateTime> startedAt = <DateTime>[];

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    startedKeywords.add(keyword);
    startedAt.add(_nowProvider());
    return const DiscuzSearchResponse(
      items: <DiscuzSearchResultItem>[],
      rateLimited: false,
    );
  }

  @override
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) async {
    return const DiscuzSearchResponse(
      items: <DiscuzSearchResultItem>[],
      rateLimited: false,
    );
  }
}
