import 'dart:io';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_interaction_controller.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/services/thread_post_comment_service.dart';
import 'package:y300/features/thread/presentation/thread_post_interaction_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../../data/comic_comment_fixtures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:y300/features/comic/presentation/comic_comment_body_projector.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_selection_copy_page.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_card.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

void main() {
  testWidgets(
    'parsed 53-image sample leaves ratings immediately after its text',
    (tester) async {
      final data =
          ThreadDetailHtmlParser(
            siteOrigin: Uri.parse('https://bbs.yamibo.com'),
          ).parse(
            File(
              'test/features/comic/data/comic_comment_image_spacing.html',
            ).readAsStringSync(),
            fallbackTid: '573314',
            fallbackPage: 1,
          );
      final source = data.posts.single;
      final images = const DefaultForumImageSourcePipeline().collectFromPost(
        source,
      );
      final projection =
          ComicCommentBodyProjector(images.map((image) => image.normalizedUrl))
              .project(
                ComicCommentContentProjection.raw(
                  ComicCommentLoadResult.fromRead(
                    commentDetailPage(posts: [source]),
                  ),
                  mode: TextConversionMode.none,
                  converterId: 'identity',
                  sourceRevision: 'sample',
                ),
              )
              .items
              .single;
      final cache = _NoopImageCacheService();
      await tester.pumpWidget(
        _host(
          ComicCommentCard(projection: projection, sourceTid: '573314'),
          imageCacheService: cache,
        ),
      );
      await tester.pumpAndSettle();
      final bodyHeight = tester.getSize(find.byType(ThreadPostHtmlBody)).height;
      final bodyBottom = tester
          .getBottomLeft(find.byType(ThreadPostHtmlBody))
          .dy;
      final ratingTop = tester
          .getTopLeft(find.byType(ThreadPostRatingSection))
          .dy;
      expect(ratingTop - bodyBottom, inInclusiveRange(0, 24));
      expect(
        find.descendant(
          of: find.byType(ThreadPostHtmlBody),
          matching: find.byType(CachedLibraryImage),
        ),
        findsNothing,
      );
      expect(
        cache.requests.where(
          (request) => request.role == ImageCacheRole.threadInline,
        ),
        isEmpty,
      );

      // An independently trimmed text-only body establishes the expected height.
      final textOnly = commentPost(
        1,
        message: source.message.substring(
          0,
          source.message.lastIndexOf('</font>') + 7,
        ),
      );
      await tester.pumpWidget(
        _host(
          ComicCommentCard(
            projection: ComicCommentItemProjection.raw(
              ComicCommentItem.fromPost(textOnly, 1),
            ),
            sourceTid: '573314',
          ),
          imageCacheService: cache,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        bodyHeight,
        closeTo(tester.getSize(find.byType(ThreadPostHtmlBody)).height, 0.5),
      );
    },
  );
  testWidgets(
    'first floor mounts its text and feedback without loading excluded comic images',
    (tester) async {
      final post = commentPost(
        1,
        message:
            '<p>comic body</p><img src="https://example.test/comic-page.jpg">',
      );
      final projection = _filteredFirstPost(post);
      final images = _NoopImageCacheService();
      await tester.pumpWidget(
        _host(
          ComicCommentCard(projection: projection, sourceTid: '100'),
          imageCacheService: images,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ForumHtmlWidgetPostRenderer), findsOneWidget);
      expect(find.byKey(const Key('thread-post-1')), findsOneWidget);
      expect(find.text('comic body', findRichText: true), findsOneWidget);
      final renderer = tester.widget<ForumHtmlWidgetPostRenderer>(
        find.byType(ForumHtmlWidgetPostRenderer),
      );
      expect(renderer.preparedDocument!.sequence.entries, isEmpty);
      expect(renderer.html, isNot(contains('comic-page.jpg')));
      expect(
        images.requests.where((r) => r.sourceUrl.contains('comic-page.jpg')),
        isEmpty,
      );
      expect(
        tester
            .widgetList<CachedLibraryImage>(find.byType(CachedLibraryImage))
            .where(
              (image) =>
                  image.request?.sourceUrl.contains('comic-page.jpg') == true,
            ),
        isEmpty,
      );
      expect(find.byType(ThreadPostRatingSection), findsOneWidget);
      expect(find.byType(ThreadPostCommentSection), findsOneWidget);
      expect(projection.displayPost.message, contains('comic-page.jpg'));
      expect(ComicCommentCard.toThreadPost(projection).isFirst, isTrue);
    },
  );
  testWidgets(
    'remaining images open a gallery containing only visible images',
    (tester) async {
      final post = commentPost(
        1,
        message:
            '<p>caption</p><img src="https://example.test/comic-page.jpg">'
            '<img src="https://example.test/extra.jpg">'
            '<img src="/static/image/smiley/face.gif">',
      );
      final projection = _filteredFirstPost(post);
      ThreadPostImageOpenRequest? opened;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ThreadPostCard(
              post: projection.renderPost,
              imageReferer: null,
              palette: ThreadDetailNativePalette.resolve(Theme.of(context)),
              onOpenPostImages: (_, request) => opened = request,
            ),
          ),
          imageCacheService: _NoopImageCacheService(),
        ),
      );
      await tester.pumpAndSettle();
      final renderer = tester.widget<ForumHtmlWidgetPostRenderer>(
        find.byType(ForumHtmlWidgetPostRenderer),
      );
      expect(renderer.html, contains('/static/image/smiley/face.gif'));
      expect(renderer.preparedDocument!.sequence.entries, hasLength(1));
      renderer.callbacks.onTapImage!(
        const ForumHtmlImageRequest(
          url: 'https://example.test/extra.jpg',
          readableIndex: 0,
        ),
      );
      expect(opened!.imageUrls, ['https://example.test/extra.jpg']);
      expect(opened!.readerRequest!.group.urls, [
        'https://example.test/extra.jpg',
      ]);
    },
  );
  testWidgets(
    'filtered first floor copies and opens selection with the complete body',
    (tester) async {
      final post = commentPost(
        1,
        message:
            '<p>comic body</p><img src="https://example.test/comic-page.jpg"><p>after image</p>',
      );
      final session = ComicCommentSessionController(
        key: const ComicCommentSessionKey(episodeId: 'e', sourceTid: '100'),
        loader: DefaultComicCommentLoader(
          repository: CommentDetailRepository(
            respond: (_) => commentDetailPage(lastPage: 1, posts: [post]),
          ),
        ),
      );
      final controller = ComicCommentInteractionController(
        session: session,
        invalidateThread: (_) async {},
      );
      addTearDown(() {
        controller.dispose();
        session.dispose();
      });
      await session.load();
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        _host(
          ComicCommentCard(
            projection: _filteredFirstPost(post),
            sourceTid: '100',
            interactionController: controller,
          ),
          imageCacheService: _NoopImageCacheService(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('thread-author-avatar-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-post-copy-all-action')));
      await tester.pumpAndSettle();
      expect(copied, contains('comic body'));
      expect(copied, contains('after image'));
      await tester.longPress(find.byKey(const Key('thread-author-avatar-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-post-select-copy-action')));
      await tester.pumpAndSettle();
      final selection = tester.widget<ThreadPostHtmlSelectionCopyPage>(
        find.byType(ThreadPostHtmlSelectionCopyPage),
      );
      expect(selection.sourcePost, same(post));
      expect(selection.post.message, contains('comic-page.jpg'));
      expect(selection.plan.images, isNotEmpty);
    },
  );
  testWidgets(
    'mobile quote markup renders identically through thread and comment cards',
    (tester) async {
      final post = commentPost(2);
      await tester.pumpWidget(
        _host(
          ComicCommentCard(
            projection: ComicCommentItemProjection.raw(
              ComicCommentItem.fromPost(post, 1),
            ),
            sourceTid: '100',
          ),
          imageCacheService: _NoopImageCacheService(),
        ),
      );
      await tester.pumpAndSettle();
      final commentHtml = tester
          .widget<ForumHtmlWidgetPostRenderer>(
            find.byType(ForumHtmlWidgetPostRenderer),
          )
          .html;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ThreadPostCard(
              post: post,
              imageReferer: null,
              palette: ThreadDetailNativePalette.resolve(Theme.of(context)),
            ),
          ),
          imageCacheService: _NoopImageCacheService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ForumHtmlWidgetPostRenderer>(
              find.byType(ForumHtmlWidgetPostRenderer),
            )
            .html,
        commentHtml,
      );
      expect(commentHtml, contains('blockquote'));
    },
  );
  testWidgets('a later floor opens the shared complete action drawer', (
    tester,
  ) async {
    final repo = CommentDetailRepository();
    final session = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'e', sourceTid: '100'),
      loader: DefaultComicCommentLoader(repository: repo),
    );
    final controller = ComicCommentInteractionController(
      session: session,
      invalidateThread: (_) async {},
    );
    addTearDown(() {
      controller.dispose();
      session.dispose();
    });
    await session.load();
    await session.loadMore();
    final item = session.state.result!.items[2];
    final comment = _RecordingCommentService();
    await tester.pumpWidget(
      _host(
        ComicCommentCard(
          projection: ComicCommentItemProjection.raw(item),
          sourceTid: '100',
          interactionController: controller,
        ),
        imageCacheService: _NoopImageCacheService(),
        commentService: comment,
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('thread-author-avatar-3')));
    await tester.pumpAndSettle();
    for (final name in [
      'reply',
      'rate',
      'comment',
      'select-copy',
      'copy-all',
      'copy-floor-link',
    ]) {
      expect(find.byKey(Key('thread-post-$name-action')), findsOneWidget);
    }
    expect(find.byKey(const Key('thread-post-action-sheet')), findsOneWidget);
    expect(repo.calls, [1, 2]);
    await tester.tap(find.byKey(const Key('thread-post-comment-action')));
    await tester.pumpAndSettle();
    expect(comment.target, ('100', '3', 2));
    expect(comment.referer?.queryParameters['page'], '2');
    expect(comment.referer?.fragment, 'pid3');
    expect(repo.calls, [1, 2]);
  });

  testWidgets(
    'Mobile comment edit notices use the shared single-line fitting',
    (tester) async {
      const notice = '本帖最后由 fixture-comment-author 于 2026-1-1 12:34 编辑';
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 280,
            child: ComicCommentCard(
              projection: ComicCommentItemProjection.raw(
                _comment(
                  rawMessage:
                      '<i class="pstatus">$notice</i><br><br><p>评论正文</p>',
                ),
              ),
              sourceTid: '10001',
            ),
          ),
          imageCacheService: _NoopImageCacheService(),
        ),
      );
      await tester.pumpAndSettle();

      final status = find.byKey(const Key('forum-html-discuz-edit-status'));
      expect(tester.widget<Text>(status).data, notice);
      expect(tester.widget<Text>(status).maxLines, 1);
      expect(
        tester
            .widget<FittedBox>(
              find.ancestor(of: status, matching: find.byType(FittedBox)),
            )
            .fit,
        BoxFit.scaleDown,
      );
      expect(find.textContaining('评论正文', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders comment metadata and shared HTML body', (tester) async {
    await tester.pumpWidget(
      _host(
        ComicCommentCard(
          projection: ComicCommentItemProjection.raw(
            _comment(
              authorName: '回复用户',
              dateline: '2026-07-19 12:30',
              floorNumber: 5,
              rawMessage: '<p>评论正文</p>',
            ),
          ),
          sourceTid: '573279',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comic-comment-card-p5')), findsOneWidget);
    expect(find.text('回复用户'), findsOneWidget);
    expect(find.text('2026-07-19 12:30'), findsOneWidget);
    expect(find.text('5#'), findsOneWidget);
    expect(find.byType(ThreadPostCard), findsOneWidget);
    final renderer = tester.widget<ForumHtmlWidgetPostRenderer>(
      find.byType(ForumHtmlWidgetPostRenderer),
    );
    expect(renderer.html, contains('评论正文'));
    final avatar = tester.widget<CachedLibraryImage>(
      find.descendant(
        of: find.byKey(const Key('thread-author-avatar-p5')),
        matching: find.byType(CachedLibraryImage),
      ),
    );
    expect(avatar.request, isNull);
    expect(
      avatar.imageProviderOverride,
      isA<AssetImage>().having(
        (provider) => provider.assetName,
        'assetName',
        forumDefaultAvatarAsset,
      ),
    );
    expect(avatar.fadeInDuration, ForumCachedAvatar.fadeInDuration);
    expect(find.byType(ThreadPostCommentSection), findsNothing);
    expect(find.byType(ThreadPostRatingSection), findsNothing);
  });

  testWidgets('uses the shared cached avatar contract for remote authors', (
    tester,
  ) async {
    const referer = 'https://bbs.yamibo.com/';
    await tester.pumpWidget(
      _host(
        ComicCommentCard(
          projection: ComicCommentItemProjection.raw(
            _comment(
              avatarUrl:
                  'https://bbs.yamibo.com/uc_server/data/avatar/000/42/20/14_avatar_middle.jpg',
            ),
          ),
          sourceTid: '573279',
          imageReferer: referer,
        ),
        imageCacheService: _NoopImageCacheService(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final avatar = tester.widget<CachedLibraryImage>(
      find.descendant(
        of: find.byKey(const Key('thread-author-avatar-p5')),
        matching: find.byType(CachedLibraryImage),
      ),
    );
    expect(avatar.request?.role, ImageCacheRole.avatar);
    expect(avatar.request?.ownerType, ImageCacheOwnerType.thread);
    expect(avatar.request?.ownerId, '422014');
    expect(avatar.referer, referer);
    expect(avatar.fadeInDuration, ForumCachedAvatar.fadeInDuration);

    final localDefault = avatar.errorPlaceholder as CachedLibraryImage;
    expect(
      localDefault.imageProviderOverride,
      isA<AssetImage>().having(
        (provider) => provider.assetName,
        'assetName',
        forumDefaultAvatarAsset,
      ),
    );
    expect(localDefault.fadeInDuration, ForumCachedAvatar.fadeInDuration);
  });

  testWidgets('passes ordinary images and emoticons to threadInline renderer', (
    tester,
  ) async {
    const html =
        '<p>正文<img src="smiley.png"></p>'
        '<img src="data/attachment/forum/comment.png">';
    await tester.pumpWidget(
      _host(
        ComicCommentCard(
          projection: ComicCommentItemProjection.raw(
            _comment(rawMessage: html),
          ),
          sourceTid: '573279',
        ),
        imageCacheService: _NoopImageCacheService(),
      ),
    );
    await tester.pump();

    final renderer = tester.widget<ForumHtmlWidgetPostRenderer>(
      find.byType(ForumHtmlWidgetPostRenderer),
    );
    expect(renderer.contentImageKind, ForumImageKind.threadInline);
    expect(renderer.html, contains('smiley.png'));
    expect(renderer.html, contains('comment.png'));
    expect(renderer.imageCacheOwnerId, 'comic-comment-573279-p5');
  });

  testWidgets('uses forum HTML preferences and follows dark theme', (
    tester,
  ) async {
    final preferences = ForumHtmlReaderPreferences.defaults().copyWith(
      preserveAuthorFontSize: false,
    );
    await tester.pumpWidget(
      _host(
        ComicCommentCard(
          projection: ComicCommentItemProjection.raw(
            _comment(rawMessage: '<span style="color:black">深色主题正文</span>'),
          ),
          sourceTid: '573279',
        ),
        theme: ThemeData.dark(useMaterial3: true),
        preferences: preferences,
      ),
    );
    await tester.pumpAndSettle();

    final renderer = tester.widget<ForumHtmlWidgetPostRenderer>(
      find.byType(ForumHtmlWidgetPostRenderer),
    );
    expect(renderer.preferences, preferences);
    expect(renderer.theme.brightness.name, 'dark');
  });

  testWidgets(
    'renders projected body and time while keeping author and resource identity raw',
    (tester) async {
      final source = _comment(
        authorName: '发型用户名',
        dateline: '软件时间',
        rawMessage: '<p>软件正文</p><img src="/raw-image.jpg">',
      );
      await tester.pumpWidget(
        _host(
          ComicCommentCard(
            projection: ComicCommentItemProjection(
              sourceItem: source,
              displayMessage: '<p>軟體正文</p><img src="/raw-image.jpg">',
              displayDateline: '軟體時間',
            ),
            sourceTid: '573279',
          ),
          imageCacheService: _NoopImageCacheService(),
        ),
      );
      await tester.pump();

      expect(find.text('发型用户名'), findsOneWidget);
      expect(find.text('髮型用戶名'), findsNothing);
      expect(find.text('軟體時間'), findsOneWidget);
      final renderer = tester.widget<ForumHtmlWidgetPostRenderer>(
        find.byType(ForumHtmlWidgetPostRenderer),
      );
      expect(renderer.html, contains('軟體正文'));
      expect(renderer.html, contains('/raw-image.jpg'));
      expect(renderer.imageCacheOwnerId, 'comic-comment-573279-p5');
    },
  );
}

ComicCommentItemProjection _filteredFirstPost(ThreadPost post) =>
    ComicCommentBodyProjector(['https://example.test/comic-page.jpg'])
        .project(
          ComicCommentContentProjection.raw(
            ComicCommentLoadResult.fromRead(commentDetailPage(posts: [post])),
            mode: TextConversionMode.none,
            converterId: 'identity',
            sourceRevision: 'fixture',
          ),
        )
        .items
        .single;

ComicCommentItem _comment({
  String authorName = '用户',
  String dateline = '刚刚',
  int floorNumber = 5,
  String rawMessage = '<p>正文</p>',
  String? avatarUrl,
}) {
  return ComicCommentItem(
    pid: 'p5',
    authorId: '422014',
    authorName: authorName,
    dateline: dateline,
    floorNumber: floorNumber,
    rawMessage: rawMessage,
    avatarUrl: avatarUrl,
  );
}

Widget _host(
  Widget child, {
  ThemeData? theme,
  ForumHtmlReaderPreferences? preferences,
  ImageCacheService? imageCacheService,
  ThreadPostCommentService? commentService,
}) {
  return ProviderScope(
    overrides: [
      if (commentService != null)
        threadPostCommentServiceProvider.overrideWithValue(commentService),
      if (preferences != null)
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          _FixedPreferencesRepository(preferences),
        ),
      if (imageCacheService != null)
        imageCacheServiceProvider.overrideWithValue(imageCacheService),
    ],
    child: LocalizedTestApp(
      theme: theme ?? ThemeData.light(useMaterial3: true),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

class _RecordingCommentService implements ThreadPostCommentService {
  (String, String, int)? target;
  Uri? referer;
  @override
  Future<DataReadResult<ThreadPostCommentForm, ThreadPostCommentCapabilities>>
  load({
    required String tid,
    required int page,
    required ThreadPost post,
    Uri? referer,
  }) async {
    target = (tid, post.pid, page);
    this.referer = referer;
    return const DataReadFailure(
      kind: DataReadFailureKind.unauthorized,
      diagnosticMessage: 'fixture_requires_login',
    );
  }

  @override
  Future<DataCommandResult<ThreadPostCommentReceipt>> submit(
    ThreadPostCommentDraft draft,
  ) => throw StateError('An unauthorized preparation must not submit');
}

final class _FixedPreferencesRepository
    implements ForumHtmlReaderPreferencesRepository {
  const _FixedPreferencesRepository(this.preferences);

  final ForumHtmlReaderPreferences preferences;

  @override
  Future<ForumHtmlReaderPreferences> load() async => preferences;

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {}
}

final class _NoopImageCacheService implements ImageCacheService {
  final List<ImageCacheRequest> requests = [];
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    requests.add(request);
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
}
