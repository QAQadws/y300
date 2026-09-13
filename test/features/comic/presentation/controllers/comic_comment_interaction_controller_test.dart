import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_interaction_controller.dart';
import 'package:y300/features/thread/domain/services/thread_interaction_context_loader.dart';
import '../../data/comic_interaction_fixtures.dart';

void main() {
  test(
    'loads the verified current thread first floor independently of comments',
    () async {
      final repo = ComicInteractionRepository();
      final result = await ThreadInteractionContextLoader(repo).load('100');
      expect(repo.calls, [(tid: '100', page: 1)]);
      expect(result.dataOrNull?.firstPost?.pid, '200');
      expect(result.dataOrNull?.canRate, isTrue);
      expect(result.dataOrNull?.canReply, isTrue);
    },
  );

  test('rejects invalid and mismatched thread or page identities', () async {
    final repo = ComicInteractionRepository([
      comicInteractionRead(tid: '999'),
      comicInteractionRead(page: 2),
    ]);
    final loader = ThreadInteractionContextLoader(repo);
    expect((await loader.load('invalid')).failureOrNull, isNotNull);
    expect(repo.calls, isEmpty);
    expect((await loader.load('100')).failureOrNull, isNotNull);
    expect((await loader.load('100')).failureOrNull, isNotNull);
  });

  test(
    'missing or ambiguous first floor and capability gates never guess a rating target',
    () async {
      final repo = ComicInteractionRepository([
        comicInteractionRead(first: false),
        comicInteractionRead(ambiguous: true),
        comicInteractionRead(rate: false),
        comicInteractionRead(fid: ''),
        comicInteractionRead(
          capabilities: ThreadDetailReadCapabilities(
            values: DataCapabilitySet.supported([
              ThreadDetailCapability.threadIdentity,
            ]),
            paginationPrecision: PaginationPrecision.exact,
          ),
        ),
      ]);
      final loader = ThreadInteractionContextLoader(repo);
      for (var i = 0; i < 3; i++) {
        final data = (await loader.load('100')).dataOrNull!;
        expect(data.canRate, isFalse);
        expect(data.canReply, isTrue);
      }
      expect((await loader.load('100')).dataOrNull!.canReply, isFalse);
      final data = (await loader.load('100')).dataOrNull!;
      expect(data.canRate, isFalse);
      expect(data.canReply, isFalse);
    },
  );

  test(
    'visibility loads once, concurrent loads share a flight, failed reads can retry',
    () async {
      final pending = Completer<ComicInteractionRead>();
      final repo = ComicInteractionRepository([pending.future]);
      final controller = _controller(repo);
      addTearDown(controller.dispose);
      controller.setVisible(true);
      final flight = controller.load();
      controller.setVisible(true);
      expect(repo.calls, hasLength(1));
      pending.complete(
        const DataReadFailure(
          kind: DataReadFailureKind.unauthorized,
          diagnosticMessage: 'unauthorized',
        ),
      );
      await flight;
      expect(
        controller.result?.failureOrNull?.kind,
        DataReadFailureKind.unauthorized,
      );
      await controller.load(force: true);
      expect(controller.context?.tid, '100');
    },
  );

  test(
    'only a proven reply refreshes comments and concurrent actions are suppressed',
    () async {
      final repo = ComicInteractionRepository();
      final invalidated = <String>[];
      var refreshed = 0;
      final controller = _controller(
        repo,
        invalidate: (tid) async => invalidated.add(tid),
        refresh: () async => refreshed++,
      );
      addTearDown(controller.dispose);
      await controller.load();
      final pending = Completer<bool>();
      var invoked = 0;
      final action = controller.perform(
        refreshComments: true,
        invoke: (target, guard) {
          expect(target.tid, '100');
          expect(target.firstPost?.pid, '200');
          invoked++;
          return pending.future;
        },
      );
      await controller.perform(
        refreshComments: true,
        invoke: (_, _) async {
          invoked++;
          return true;
        },
      );
      expect(invoked, 1);
      pending.complete(true);
      await action;
      expect(invalidated, ['100']);
      expect(refreshed, 1);
      await controller.perform(
        refreshComments: true,
        invoke: (_, _) async => false,
      );
      expect(refreshed, 1);
      await controller.perform(
        refreshComments: false,
        invoke: (_, _) async => true,
      );
      expect(invalidated, ['100', '100']);
      expect(refreshed, 1);
    },
  );

  test(
    'disposed chapter still invalidates its proven write without refreshing a new chapter',
    () async {
      final invalidated = <String>[];
      var refreshed = 0;
      final controller = _controller(
        ComicInteractionRepository(),
        invalidate: (tid) async => invalidated.add(tid),
        refresh: () async => refreshed++,
      );
      await controller.load();
      final pending = Completer<bool>();
      late bool Function() guard;
      final action = controller.perform(
        refreshComments: true,
        invoke: (_, current) {
          guard = current;
          return pending.future;
        },
      );
      controller.dispose();
      expect(guard(), isFalse);
      pending.complete(true);
      await action;
      expect(invalidated, ['100']);
      expect(refreshed, 0);
    },
  );

  test('session reset discards a late context load', () async {
    final old = Completer<ComicInteractionRead>();
    final repo = ComicInteractionRepository([
      old.future,
      comicInteractionRead(fid: '88'),
    ]);
    final controller = _controller(repo);
    addTearDown(controller.dispose);
    controller.setVisible(true);
    final flight = controller.load();
    controller.resetSession();
    await Future<void>.delayed(Duration.zero);
    await controller.load();
    old.complete(comicInteractionRead(fid: '33'));
    await flight;
    expect(controller.context?.fid, '88');
  });
}

ComicCommentInteractionController _controller(
  ComicInteractionRepository repository, {
  Future<void> Function(String)? invalidate,
  Future<void> Function()? refresh,
}) => ComicCommentInteractionController(
  sourceTid: '100',
  loader: ThreadInteractionContextLoader(repository),
  invalidateThread: invalidate ?? (_) async {},
  refreshComments: refresh ?? () async {},
);
