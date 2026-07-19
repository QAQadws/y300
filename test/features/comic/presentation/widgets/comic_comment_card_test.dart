import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_card.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

void main() {
  testWidgets('renders comment metadata and shared HTML body', (tester) async {
    await tester.pumpWidget(
      _host(
        ComicCommentCard(
          comment: _comment(
            authorName: '回复用户',
            dateline: '2026-07-19 12:30',
            floorNumber: 5,
            rawMessage: '<p>评论正文</p>',
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
    expect(find.byType(CachedLibraryImage), findsNothing);
    expect(find.byType(ThreadPostCommentSection), findsNothing);
    expect(find.byType(ThreadPostRatingSection), findsNothing);
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
          comment: _comment(rawMessage: html),
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
          comment: _comment(
            rawMessage: '<span style="color:black">深色主题正文</span>',
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
}

ComicCommentItem _comment({
  String authorName = '用户',
  String dateline = '刚刚',
  int floorNumber = 5,
  String rawMessage = '<p>正文</p>',
}) {
  return ComicCommentItem(
    pid: 'p5',
    authorId: '422014',
    authorName: authorName,
    dateline: dateline,
    floorNumber: floorNumber,
    rawMessage: rawMessage,
    avatarUrl: null,
  );
}

Widget _host(
  Widget child, {
  ThemeData? theme,
  ForumHtmlReaderPreferences? preferences,
  ImageCacheService? imageCacheService,
}) {
  return ProviderScope(
    overrides: [
      if (preferences != null)
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          _FixedPreferencesRepository(preferences),
        ),
      if (imageCacheService != null)
        imageCacheServiceProvider.overrideWithValue(imageCacheService),
    ],
    child: MaterialApp(
      theme: theme ?? ThemeData.light(useMaterial3: true),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
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
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
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
