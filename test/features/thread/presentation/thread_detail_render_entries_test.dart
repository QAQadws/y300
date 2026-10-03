import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projection.dart';
import 'package:y300/features/thread/presentation/thread_detail_render_entries.dart';

void main() {
  const planner = ThreadDetailRenderEntryPlanner();

  group('ThreadDetailRenderEntryPlanner', () {
    test('splits only the body-end target and retains an empty footer', () {
      final posts = [_post('before', 1), _post('target', 2), _post('after', 3)];
      final entries = planner.buildEntries(
        posts: posts,
        targetPid: 'target',
        landing: ThreadPostLanding.bodyEnd,
      );

      expect(entries.map((entry) => entry.kind), [
        ThreadDetailRenderEntryKind.postCard,
        ThreadDetailRenderEntryKind.postHeader,
        ThreadDetailRenderEntryKind.postBody,
        ThreadDetailRenderEntryKind.postFooter,
        ThreadDetailRenderEntryKind.postCard,
        ThreadDetailRenderEntryKind.pagination,
        ThreadDetailRenderEntryKind.targetSpacer,
      ]);
      expect(entries.map((entry) => entry.key), [
        'thread-post-card-entry-before',
        'thread-post-header-entry-target',
        'thread-post-body-entry-target',
        'thread-post-footer-entry-target',
        'thread-post-card-entry-after',
        'thread-detail-pagination',
        'thread-detail-target-scroll-spacer',
      ]);
      expect(entries.take(5).map((entry) => entry.postIndex), [0, 1, 1, 1, 2]);
      for (final entry in entries.sublist(1, 4)) {
        expect(entry.sourcePost, same(posts[1]));
        expect(entry.displayPost, same(posts[1]));
      }
    });

    test('top landing keeps the target as a single visual card', () {
      final entries = planner.buildEntries(
        posts: [_post('target', 1)],
        targetPid: 'target',
      );

      expect(entries.map((entry) => entry.kind), [
        ThreadDetailRenderEntryKind.postCard,
        ThreadDetailRenderEntryKind.pagination,
        ThreadDetailRenderEntryKind.targetSpacer,
      ]);
    });

    test('normalizes surrounding whitespace in the target pid', () {
      final entries = planner.buildEntries(
        posts: [_post('target', 1)],
        targetPid: ' target ',
        landing: ThreadPostLanding.bodyEnd,
      );

      expect(entries.map((entry) => entry.kind), [
        ThreadDetailRenderEntryKind.postHeader,
        ThreadDetailRenderEntryKind.postBody,
        ThreadDetailRenderEntryKind.postFooter,
        ThreadDetailRenderEntryKind.pagination,
        ThreadDetailRenderEntryKind.targetSpacer,
      ]);
    });

    test('an absent target keeps existing cards and the landing spacer', () {
      final entries = planner.buildEntries(
        posts: [_post('before', 1), _post('after', 2)],
        targetPid: 'not-loaded',
        landing: ThreadPostLanding.bodyEnd,
      );

      expect(entries.map((entry) => entry.kind), [
        ThreadDetailRenderEntryKind.postCard,
        ThreadDetailRenderEntryKind.postCard,
        ThreadDetailRenderEntryKind.pagination,
        ThreadDetailRenderEntryKind.targetSpacer,
      ]);
      expect(entries.take(2).map((entry) => entry.postIndex), [0, 1]);
    });

    test('omits the landing spacer when no target is requested', () {
      for (final targetPid in <String?>[null, '', '  ']) {
        final entries = planner.buildEntries(
          posts: [_post('p1', 1)],
          targetPid: targetPid,
          landing: ThreadPostLanding.bodyEnd,
        );

        expect(entries.map((entry) => entry.kind), [
          ThreadDetailRenderEntryKind.postCard,
          ThreadDetailRenderEntryKind.pagination,
        ]);
      }
    });

    test('keeps long text and image bodies as one visual card', () {
      for (final message in [
        '<p>${List.filled(1000, '长正文').join()}</p>',
        '<p>开头</p><img file="data/attachment/forum/1.jpg"><img file="data/attachment/forum/2.jpg"><p>结尾</p>',
      ]) {
        final post = _post('body', 1, message: message);
        final entries = planner.buildEntries(posts: [post]);

        expect(entries.map((entry) => entry.kind), [
          ThreadDetailRenderEntryKind.postCard,
          ThreadDetailRenderEntryKind.pagination,
        ]);
        expect(entries.first.key, 'thread-post-card-entry-body');
        expect(entries.first.sourcePost, same(post));
        expect(entries.first.displayPost, same(post));
        expect(entries.first.displayPost!.message, message);
      }
    });

    test('keeps source identity and the complete display projection', () {
      final source = _post('source-pid', 1, message: '<p>原文</p>');
      final display = _post('display-pid', 1, message: '<p>顯示正文</p>');
      final entries = planner.buildProjectionEntries(
        posts: [
          ThreadDetailPostProjection(sourcePost: source, displayPost: display),
        ],
        targetPid: source.pid,
        landing: ThreadPostLanding.bodyEnd,
      );

      expect(entries.take(3).map((entry) => entry.key), [
        'thread-post-header-entry-source-pid',
        'thread-post-body-entry-source-pid',
        'thread-post-footer-entry-source-pid',
      ]);
      for (final entry in entries.take(3)) {
        expect(entry.sourcePost, same(source));
        expect(entry.displayPost, same(display));
        expect(entry.postIndex, 0);
      }
    });

    test(
      'empty results still expose pagination and return immutable entries',
      () {
        final entries = planner.buildEntries(posts: const []);

        expect(entries.single.kind, ThreadDetailRenderEntryKind.pagination);
        expect(entries.single.sourcePost, isNull);
        expect(entries.single.displayPost, isNull);
        expect(entries.single.postIndex, -1);
        expect(
          () => entries.add(const ThreadDetailRenderEntry.targetSpacer()),
          throwsUnsupportedError,
        );
      },
    );
  });
}

ThreadPost _post(String pid, int number, {String message = '<p>正文</p>'}) =>
    ThreadPost(
      pid: pid,
      author: 'alice',
      authorId: '1',
      message: message,
      number: number,
      isFirst: number == 1,
      dateline: 'today',
    );
