import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/novel/data/services/thread_post_locator_novel_chapter_source_route_resolver.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';

void main() {
  test('uses findpost and returns the ordinary thread page', () async {
    final locator = _FakeThreadPostLocator(
      const ApiSuccess<ThreadPostLocation>(
        ThreadPostLocation(
          tid: '521519',
          pid: '41397522',
          page: 722,
          url: 'https://bbs.yamibo.com/thread-521519-722-1.html#pid41397522',
        ),
      ),
    );
    final resolver = ThreadPostLocatorNovelChapterSourceRouteResolver(
      locator: locator,
    );

    final route = await resolver.resolve(
      const NovelChapterSourceReference(tid: '521519', pid: '41397522'),
    );

    expect(route.page, 722);
    expect(route.pid, '41397522');
    expect(locator.lastTid, '521519');
    expect(locator.lastPid, '41397522');
    expect(locator.lastSourceUri?.queryParameters, <String, String>{
      'mod': 'redirect',
      'goto': 'findpost',
      'ptid': '521519',
      'pid': '41397522',
    });
  });

  test('surfaces locator failure without guessing a page', () async {
    final resolver = ThreadPostLocatorNovelChapterSourceRouteResolver(
      locator: _FakeThreadPostLocator(
        const ApiFailure<ThreadPostLocation>(
          ApiError(type: ApiErrorType.parse, message: '目标楼层不存在'),
        ),
      ),
    );

    await expectLater(
      resolver.resolve(
        const NovelChapterSourceReference(tid: '521519', pid: '1'),
      ),
      throwsA(
        isA<NovelChapterSourceRouteException>().having(
          (error) => error.code,
          'code',
          NovelChapterSourceRouteFailureCode.emptyResult,
        ),
      ),
    );
  });

  test('rejects mismatched and invalid source identities', () async {
    final resolver = ThreadPostLocatorNovelChapterSourceRouteResolver(
      locator: _FakeThreadPostLocator(
        const ApiSuccess<ThreadPostLocation>(
          ThreadPostLocation(
            tid: '999',
            pid: '2',
            page: 3,
            url: 'https://bbs.yamibo.com/thread-999-3-1.html',
          ),
        ),
      ),
    );

    await expectLater(
      resolver.resolve(
        const NovelChapterSourceReference(tid: '521519', pid: '2'),
      ),
      throwsA(isA<NovelChapterSourceRouteException>()),
    );
    await expectLater(
      resolver.resolve(
        const NovelChapterSourceReference(tid: '521519', pid: ''),
      ),
      throwsA(isA<NovelChapterSourceRouteException>()),
    );
  });
}

class _FakeThreadPostLocator implements ThreadPostLocator {
  _FakeThreadPostLocator(this.result);

  final ApiResult<ThreadPostLocation> result;
  String? lastTid;
  String? lastPid;
  Uri? lastSourceUri;

  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) async {
    lastTid = tid;
    lastPid = pid;
    lastSourceUri = sourceUri;
    return result;
  }
}
