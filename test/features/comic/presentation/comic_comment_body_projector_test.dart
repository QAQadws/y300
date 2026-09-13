import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/thread/data/services/thread_detail_document_decoder.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/comic_comment_body_projector.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../data/comic_comment_fixtures.dart';

const _comic = 'https://bbs.yamibo.com/data/attachment/forum/comic.jpg';

void main() {
  test('only affected image runs are compacted between retained paragraphs', () {
    const credits = '<p>credits<br><br><br>license</p>';
    const extra =
        '<blockquote>quote<br><br><img src="/extra.jpg"></blockquote>';
    final post = _post(
      1,
      body:
          '$credits<font>before</font><br><br>'
          '<div><a><img src="$_comic"></a><br><span><img src="$_comic"></span></div>'
          '<br>\n<br><img src="$_comic"><br><font>after</font>$extra',
    );
    final rendered = ComicCommentBodyProjector([
      _comic,
    ]).project(_projection([post])).items.single.renderPost.message;
    expect(
      rendered,
      '$credits<font>before</font><br><br><font>after</font>$extra',
    );
  });
  test(
    'mobile sample removes all 52 separators between its 53 reader images',
    () {
      final data =
          ThreadDetailDocumentDecoder(
            createY300ThreadDetailHtmlDecoder(),
          ).decode(
            File(
              'test/features/comic/data/comic_comment_image_spacing.html',
            ).readAsStringSync(),
            fallbackTid: '573314',
            fallbackPage: 1,
          );
      final post = data.posts.single;
      final images = const DefaultForumImageSourcePipeline().collectFromPost(
        post,
      );
      expect(images, hasLength(53));
      final rendered = ComicCommentBodyProjector(
        images.map((e) => e.normalizedUrl),
      ).project(_projection([post])).items.single.renderPost;
      final before = html.parseFragment(post.message);
      final after = html.parseFragment(rendered.message);
      expect(after.text?.trim(), before.text?.trim());
      expect(after.querySelectorAll('img'), isEmpty);
      final lastText = after.querySelector('font[color="Red"]')!;
      final trailing = after.nodes.skip(after.nodes.indexOf(lastText) + 1);
      expect(
        trailing.where(
          (node) =>
              node is dom.Element || (node.text?.trim().isNotEmpty ?? false),
        ),
        isEmpty,
      );
    },
  );
  test('only matched images in the consecutive OP run are hidden', () {
    final source = _projection([
      _post(1),
      _post(2),
      _post(3, uid: '8'),
      _post(4),
    ]);
    final result = ComicCommentBodyProjector([_comic]).project(source);
    for (var i = 0; i < 2; i++) {
      expect(result.items[i].renderPost.message, isNot(contains('<img')));
      expect(result.items[i].displayPost.message, contains(_comic));
      expect(result.items[i].sourceItem, same(source.items[i].sourceItem));
    }
    for (var i = 2; i < 4; i++) {
      expect(result.items[i], same(source.items[i]));
      expect(result.items[i].renderPost.message, contains(_comic));
    }
    expect(result.sourceResult, same(source.sourceResult));
  });

  test(
    'URL variants and explicit attachment IDs exclude duplicate thumbnails',
    () {
      const body =
          '<div class="img"><a href="$_comic">'
          '<img id="aimg_9" src="/thumb.jpg" zoomfile="//bbs.yamibo.com/data/attachment/forum/comic.jpg#full">'
          '</a><br></div>'
          '<img aid="9" src="/other-thumb.jpg">'
          '<img id="aimg_10" src="/attachment-thumb.jpg">'
          '<img src="data/attachment/forum/comic.jpg">'
          '<img file="$_comic" src="/placeholder.jpg">'
          '<img data-original="$_comic" src="/placeholder2.jpg">'
          '<img data-src="$_comic" src="/placeholder3.jpg">'
          '<p>caption <a href="/next">next chapter</a></p>'
          '<blockquote>quote text<img src="$_comic"></blockquote>'
          '<img src="/extra.jpg">'
          '<img src="/static/image/smiley/face.gif">';
      final attachments = [
        _attachment('9', '/different-full.jpg'),
        _attachment('10', _comic),
        _attachment('11', '/extra.jpg'),
        _attachment('12', '/document.zip', image: false),
      ];
      final source = _projection([
        _post(1, body: body, attachments: attachments),
      ]);
      final result = ComicCommentBodyProjector([
        _comic,
        'https://bbs.yamibo.com/static/image/smiley/face.gif',
      ]).project(source).items.single.renderPost;
      final fragment = html.parseFragment(result.message);
      expect(fragment.querySelector('.img'), isNull);
      expect(fragment.querySelectorAll('img').map((e) => e.attributes['src']), [
        '/extra.jpg',
        '/static/image/smiley/face.gif',
      ]);
      expect(fragment.querySelector('blockquote')?.text, 'quote text');
      expect(fragment.querySelector('a')?.attributes['href'], '/next');
      expect(fragment.text, contains('caption'));
      expect(result.attachmentImages.map((e) => e.aid), ['11', '12']);
      expect(
        source.items.single.sourceItem.post.attachmentImages,
        hasLength(4),
      );
    },
  );

  test(
    'unknown images, query variants and meaningful wrapping content remain',
    () {
      const body =
          '<p>before<img src="$_comic">after</p>'
          '<a href="/link">label<img src="$_comic"></a>'
          '<details><summary>fold title</summary><p>fold text<img src="$_comic"></p></details>'
          '<img src="$_comic?variant=2">'
          '<img src="https://other.test/data/attachment/forum/comic.jpg">'
          '<img src="data:image/gif;base64,AAAA">';
      final result = ComicCommentBodyProjector([
        _comic,
      ]).project(_projection([_post(1, body: body)])).items.single.renderPost;
      final fragment = html.parseFragment(result.message);
      expect(fragment.querySelector('p')?.text, 'beforeafter');
      expect(fragment.querySelector('a')?.text, 'label');
      expect(fragment.querySelector('summary')?.text, 'fold title');
      expect(fragment.querySelector('details')?.text, contains('fold text'));
      expect(fragment.querySelectorAll('img'), hasLength(3));
    },
  );

  test(
    'missing first floor, gaps, guests and conflicting first identity are preserved',
    () {
      final projector = ComicCommentBodyProjector([_comic]);
      for (final posts in [
        [_post(2)],
        [_post(1, uid: '')],
        [_post(1, uid: '0')],
        [_post(1), _post(2, isFirst: true)],
      ]) {
        final source = _projection(posts);
        expect(projector.project(source), same(source));
      }
      final gap = projector.project(_projection([_post(1), _post(3)]));
      expect(gap.items.last.renderPost.message, contains(_comic));
    },
  );

  test(
    'deduplicated pages continue the OP run without a layout revision for append',
    () {
      final first = ComicCommentLoadResult.fromRead(
        commentDetailPage(posts: [_post(1), _post(2)]),
      );
      final next = ComicCommentLoadResult.fromRead(
        commentDetailPage(
          page: 2,
          posts: [
            _post(1),
            _post(3),
            _post(4, uid: '8'),
          ],
        ),
      );
      final projector = ComicCommentBodyProjector([_comic]);
      final tracker = ComicCommentLayoutRevisionTracker();
      final before = projector.project(_raw(first));
      final after = projector.project(
        _raw(ComicCommentLoadResult.merge('100', {1: first, 2: next})),
      );
      expect(tracker.update(before), 0);
      expect(tracker.update(after), 0);
      expect(after.items.map((e) => e.sourceItem.pid), ['1', '2', '3', '4']);
      expect(after.items[2].sourceItem.sourcePage, 2);
      expect(after.items[2].renderPost.message, isNot(contains('<img')));
      expect(after.items.last.renderPost.message, contains(_comic));
    },
  );

  test(
    'conversion and refresh preserve complete posts and update rendered layout',
    () {
      final post = commentPost(1, message: '<p>软件</p><img src="$_comic">');
      final source = _projection([post]);
      final converted = ComicCommentContentProjection(
        sourceResult: source.sourceResult,
        items: [
          ComicCommentItemProjection(
            sourceItem: source.items.single.sourceItem,
            displayMessage: post.message.replaceAll('软件', '軟體'),
            displayDateline: post.dateline,
          ),
        ],
        mode: TextConversionMode.toTraditional,
        converterId: 'fixture',
        sourceRevision: 'converted',
        isConverted: true,
      );
      final projector = ComicCommentBodyProjector([_comic]);
      final result = projector.project(converted);
      final item = result.items.single;
      expect(item.renderPost.message, '<p>軟體</p>');
      expect(item.displayPost.message, contains(_comic));
      expect(item.sourceItem.post, same(post));
      expect(item.sourceItem.post.message, contains('软件'));
      expect(
        item.renderPost.ratingSummary,
        same(item.displayPost.ratingSummary),
      );
      expect(item.renderPost.comments, same(item.displayPost.comments));
      expect(item.renderPost.replyUrl, post.replyUrl);
      expect(item.renderPost.editUrl, post.editUrl);
      final tracker = ComicCommentLayoutRevisionTracker();
      expect(tracker.update(projector.project(source)), 0);
      expect(tracker.update(result), 1);
      expect(tracker.update(projector.project(converted)), 1);
      final refreshed = _projection([
        _post(1, body: '<p>edited</p><img src="$_comic">'),
      ]);
      expect(tracker.update(projector.project(refreshed)), 2);
    },
  );

  test(
    'changed chapter image sets invalidate rendering without mutating earlier projections',
    () {
      final source = _projection([_post(1)]);
      final filtered = ComicCommentBodyProjector([_comic]).project(source);
      final otherChapter = ComicCommentBodyProjector([
        'https://other.test/page.jpg',
      ]).project(source);
      final tracker = ComicCommentLayoutRevisionTracker();
      expect(tracker.update(filtered), 0);
      expect(tracker.update(otherChapter), 1);
      expect(otherChapter.displayIdentity, isNot(filtered.displayIdentity));
      expect(otherChapter.items.single.renderPost.message, contains(_comic));
      expect(filtered.items.single.renderPost.message, isNot(contains('<img')));
      expect(ComicCommentBodyProjector([]).project(source), same(source));
    },
  );
}

ComicCommentContentProjection _projection(List<ThreadPost> posts) =>
    _raw(ComicCommentLoadResult.fromRead(commentDetailPage(posts: posts)));

ComicCommentContentProjection _raw(ComicCommentLoadResult source) =>
    ComicCommentContentProjection.raw(
      source,
      mode: TextConversionMode.none,
      converterId: 'identity',
      sourceRevision: 'fixture',
    );

ThreadPost _post(
  int number, {
  String uid = '7',
  String? body,
  bool? isFirst,
  List<ForumPostAttachmentImage> attachments = const [],
}) => ThreadPost(
  pid: '$number',
  author: 'author',
  authorId: uid,
  message: body ?? '<p>text $number</p><div><img src="$_comic"></div>',
  number: number,
  isFirst: isFirst ?? number == 1,
  dateline: 'today',
  attachmentImages: attachments,
);

ForumPostAttachmentImage _attachment(
  String aid,
  String url, {
  bool image = true,
}) => ForumPostAttachmentImage(
  aid: aid,
  url: '',
  attachment: url,
  filename: image ? 'page.jpg' : 'document.zip',
  attachimg: image ? '1' : '0',
  ext: image ? 'jpg' : 'zip',
);
