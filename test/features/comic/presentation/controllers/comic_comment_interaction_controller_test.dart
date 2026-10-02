import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
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

  test('visibility and explicit expansion share the first read', () async {
    final pending = Completer<ComicInteractionRead>();
    final repo = ComicInteractionRepository([pending.future]);
    final controller = _controller(repo);
    controller.setVisible(true);
    final load = controller.session.load();
    pending.complete(comicInteractionRead());
    await load;
    expect(repo.calls, hasLength(1));
    expect(controller.context?.canComment, isTrue);
    expect(controller.session.state.isExpanded, isTrue);
  });
  test(
    'only proven writes refresh and concurrent actions are suppressed',
    () async {
      final repo = ComicInteractionRepository();
      final invalidated = <String>[];
      final controller = _controller(
        repo,
        invalidate: (tid) async => invalidated.add(tid),
      );
      await controller.load();
      final pending = Completer<bool>();
      var invoked = 0;
      final action = controller.perform(
        invoke: (_, _) {
          invoked++;
          return pending.future;
        },
      );
      await controller.perform(
        invoke: (_, _) async {
          invoked++;
          return true;
        },
      );
      expect(invoked, 1);
      pending.complete(true);
      await action;
      expect(invalidated, ['100']);
      expect(repo.calls, hasLength(2));
      await controller.perform(invoke: (_, _) async => false);
      expect(repo.calls, hasLength(2));
      await controller.perform(page: 1, invoke: (_, _) async => true);
      expect(repo.calls, hasLength(3));
    },
  );
  test(
    'disposed owner invalidates its applied write without refreshing',
    () async {
      final repo = ComicInteractionRepository();
      final invalidated = <String>[];
      final controller = _controller(
        repo,
        invalidate: (tid) async => invalidated.add(tid),
        autoDispose: false,
      );
      await controller.load();
      final pending = Completer<bool>();
      late bool Function() guard;
      final action = controller.perform(
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
      expect(repo.calls, hasLength(1));
      controller.session.dispose();
    },
  );
  test('account reset rejects the late old first-page read', () async {
    final pending = Completer<ComicInteractionRead>();
    final repo = ComicInteractionRepository([
      pending.future,
      comicInteractionRead(fid: '88'),
    ]);
    final controller = _controller(repo);
    controller.setVisible(true);
    final old = controller.load();
    await controller.session.resetSession();
    pending.complete(comicInteractionRead(fid: '33'));
    await old;
    expect(controller.context?.fid, '88');
  });
}

ComicCommentInteractionController _controller(
  ComicInteractionRepository repo, {
  Future<void> Function(String)? invalidate,
  bool autoDispose = true,
}) {
  final session = ComicCommentSessionController(
    key: const ComicCommentSessionKey(episodeId: 'e', sourceTid: '100'),
    loader: DefaultComicCommentLoader(repository: repo),
  );
  final controller = ComicCommentInteractionController(
    session: session,
    invalidateThread: invalidate ?? (_) async {},
  );
  if (autoDispose) {
    addTearDown(() {
      controller.dispose();
      session.dispose();
    });
  }
  return controller;
}
