import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_render_context.dart';

void main() {
  test('caches render plans and isolates comment owners', () {
    final context = ThreadPostRenderContext(
      palette: ThreadDetailNativePalette.resolve(
        ThemeData.light(useMaterial3: true),
      ),
      imageHeaderBuilder: null,
      renderOwnerFor: (post) => ThreadPostRenderContext.commentRenderOwner(
        sourceTid: '573279',
        pid: post.pid,
      ),
    );
    final first = ThreadPost(
      pid: 'p1',
      author: '用户',
      authorId: '8',
      message: '<p>正文</p>',
      number: 2,
      isFirst: false,
      dateline: '刚刚',
    );

    expect(context.planFor(first), same(context.planFor(first)));
    expect(context.renderOwnerFor(first), 'comic-comment-573279-p1');
    final second = ThreadPost(
      pid: 'p2',
      author: first.author,
      authorId: first.authorId,
      message: first.message,
      number: 3,
      isFirst: false,
      dateline: first.dateline,
    );
    expect(
      context.renderOwnerFor(first),
      isNot(context.renderOwnerFor(second)),
    );
  });

  test('read-only policy disables post interactions and footer sections', () {
    const policy = ThreadPostCardInteractionPolicy.readOnly();

    expect(policy.allowAuthorProfile, isFalse);
    expect(policy.allowImageOpen, isFalse);
    expect(policy.allowPostActions, isFalse);
    expect(policy.showPoll, isFalse);
    expect(policy.showComments, isFalse);
    expect(policy.showRating, isFalse);
  });
}
