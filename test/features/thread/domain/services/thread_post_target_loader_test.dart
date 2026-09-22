import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/domain/services/thread_post_route_resolver.dart';
import 'package:y300/features/thread/domain/services/thread_post_target_loader.dart';

void main() {
  final target = ThreadPostTarget(tid: '100', pid: '200', pageHint: 9);

  test('ordinary hint is unverified and does not call locator', () async {
    final locator = _Locator();
    final result = await ThreadPostRouteResolver(locator).resolve(target);
    expect(result.dataOrNull?.page, 9);
    expect(locator.calls, 0);
  });

  for (final parameter in [
    'authorid=10',
    'ordertype=1',
    'ordertype=2',
    'viewpid=200',
    'ppp=200',
  ]) {
    test(
      'discards view-specific page and source parameters: $parameter',
      () async {
        final locator = _Locator();
        final result = await ThreadPostRouteResolver(locator).resolve(
          ThreadPostTarget.fromLink(
            tid: '100',
            pid: '200',
            pageHint: 9,
            sourceUri: Uri.parse(
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=9&$parameter#pid200',
            ),
          ),
        );
        expect(result.dataOrNull?.page, 3);
        expect(locator.sourceUri!.queryParameters, {
          'mod': 'redirect',
          'goto': 'findpost',
          'ptid': '100',
          'pid': '200',
        });
      },
    );
  }

  test('invalid identity cannot use a hint or call locator', () async {
    final locator = _Locator();
    final result = await ThreadPostRouteResolver(
      locator,
    ).resolve(ThreadPostTarget(tid: '100', pid: '', pageHint: 1));
    expect(result.isFailure, isTrue);
    expect(locator.calls, 0);
  });

  test('does not accept locator identity mismatch', () async {
    final locator = _Locator()
      ..result = const ApiSuccess(
        ThreadPostLocation(tid: '101', pid: '200', page: 3, url: ''),
      );
    expect(
      (await ThreadPostRouteResolver(
        locator,
      ).resolve(ThreadPostTarget(tid: '100', pid: '200'))).isFailure,
      isTrue,
    );
  });

  test('correct hinted page needs no recovery', () async {
    final locator = _Locator();
    var invalidations = 0;
    final result = await ThreadPostTargetLoader(
      readPage: (page) async => _page(page),
      resolver: ThreadPostRouteResolver(locator),
      invalidate: () async {
        invalidations++;
      },
    ).load(target: target, page: 9, isCurrent: () => true);
    expect(result.dataOrNull?.currentPage, 9);
    expect(locator.calls, 0);
    expect(invalidations, 0);
  });

  for (final locatedPage in [3, 9]) {
    test(
      'relocates and invalidates before rereading page $locatedPage',
      () async {
        final locator = _Locator(page: locatedPage);
        var invalidated = false;
        final reads = <int>[];
        final loader = ThreadPostTargetLoader(
          readPage: (page) async {
            reads.add(page);
            return _page(page, pid: invalidated ? '200' : '199');
          },
          resolver: ThreadPostRouteResolver(locator),
          invalidate: () async {
            invalidated = true;
          },
        );
        final result = await loader.load(
          target: target,
          page: 9,
          isCurrent: () => true,
        );
        expect(result.dataOrNull?.posts.single.pid, '200');
        expect(reads, [9, locatedPage]);
        expect(locator.calls, 1);
      },
    );
  }

  test(
    'missing after recovery stops, explicit retry starts a new attempt',
    () async {
      final locator = _Locator();
      var reads = 0;
      final loader = ThreadPostTargetLoader(
        readPage: (page) async {
          reads++;
          return _page(page, pid: '199');
        },
        resolver: ThreadPostRouteResolver(locator),
        invalidate: () async {},
      );
      for (var attempt = 1; attempt <= 2; attempt++) {
        final result = await loader.load(
          target: target,
          page: 9,
          isCurrent: () => true,
        );
        expect(result.failureOrNull?.code, 'thread_post_target_unconfirmed');
        expect(reads, attempt * 2);
        expect(locator.calls, attempt);
      }
    },
  );

  for (final kind in [
    DataReadFailureKind.network,
    DataReadFailureKind.unauthorized,
    DataReadFailureKind.server,
  ]) {
    test('$kind never triggers relocation', () async {
      final locator = _Locator();
      final failure =
          DataReadFailure<ThreadDetailData, ThreadDetailReadCapabilities>(
            kind: kind,
            code: 'fixture_failure',
            diagnosticMessage: 'private payload',
          );
      final result = await ThreadPostTargetLoader(
        readPage: (_) async => failure,
        resolver: ThreadPostRouteResolver(locator),
        invalidate: () async => fail('unexpected invalidation'),
      ).load(target: target, page: 9, isCurrent: () => true);
      expect(result, same(failure));
      expect(locator.calls, 0);
    });
  }

  test('wrong thread cannot be treated as a wrong page', () async {
    final locator = _Locator();
    final result = await ThreadPostTargetLoader(
      readPage: (page) async => _page(page, tid: '101'),
      resolver: ThreadPostRouteResolver(locator),
      invalidate: () async {},
    ).load(target: target, page: 9, isCurrent: () => true);
    expect(result.isSuccess, isFalse);
    expect(locator.calls, 0);
  });

  test(
    'owner invalidation during locate prevents cache mutation and reread',
    () async {
      final pending = Completer<ApiResult<ThreadPostLocation>>();
      final locator = _Locator()..pending = pending.future;
      var current = true;
      var reads = 0;
      final future = ThreadPostTargetLoader(
        readPage: (page) async {
          reads++;
          return _page(page, pid: '199');
        },
        resolver: ThreadPostRouteResolver(locator),
        invalidate: () async => fail('stale invalidation'),
      ).load(target: target, page: 9, isCurrent: () => current);
      await Future<void>.delayed(Duration.zero);
      current = false;
      pending.complete(locator.result);
      expect((await future).failureOrNull?.kind, DataReadFailureKind.cancelled);
      expect(reads, 1);
    },
  );
}

ThreadPostTargetRead _page(
  int page, {
  String tid = '100',
  String pid = '200',
}) => DataReadSuccess(
  data: ThreadDetailData(
    tid: tid,
    fid: '1',
    subject: 'Fixture',
    author: 'Author',
    replies: 60,
    views: 1,
    currentPage: page,
    perPage: 20,
    posts: [
      ThreadPost(
        pid: pid,
        author: 'Author',
        authorId: '10',
        message: '<p>Body</p>',
        number: 41,
        isFirst: false,
        dateline: '',
      ),
    ],
  ),
  capabilities: ThreadDetailReadCapabilities(
    paginationPrecision: PaginationPrecision.exact,
    values: DataCapabilitySet.supported(ThreadDetailCapability.values),
  ),
  metadata: const DataReadMetadata.network(),
);

class _Locator implements ThreadPostLocator {
  _Locator({int page = 3})
    : result = ApiSuccess(
        ThreadPostLocation(tid: '100', pid: '200', page: page, url: ''),
      );
  ApiResult<ThreadPostLocation> result;
  Future<ApiResult<ThreadPostLocation>>? pending;
  var calls = 0;
  Uri? sourceUri;
  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) async {
    calls++;
    this.sourceUri = sourceUri;
    return pending == null ? result : await pending!;
  }
}
