import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_preview.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:y300/features/profile/presentation/blog/blog_image_reader_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_image_reader_capability.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_detail_fixture.dart';
import '../test_support/blog_visual_fixture.dart';

const _url = 'https://example.test/body.png';
const _html =
    '<p>readable body before the image</p>'
    '<img src="$_url" width="120" height="80">'
    '<img src="$_url" width="120" height="80">';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'reader_pref_mode': 'vertical',
    }),
  );

  for (final source in ['article', 'comment', 'preview']) {
    testWidgets(
      '$source opens the tapped image without a second article read and restores position',
      (tester) async {
        final host = _Host();
        await host.pump(tester, source);
        final sourceId = _sourceId(source);
        final target = find.byKey(
          Key('thread-post-html-first-readable-image-$sourceId-1'),
        );
        await tester.ensureVisible(target);
        await tester.pump();
        final before = tester.getTopLeft(target);
        final gesture = tester.widget<GestureDetector>(target);
        await _tapImage(tester, target);
        expect(find.byType(BlogImageReaderPage), findsOneWidget);
        // A stale double tap on the covered source cannot stack a second reader.
        gesture.onTap!();
        await _frames(tester);
        expect(find.byType(BlogImageReaderPage), findsOneWidget);
        final capability =
            tester
                    .widget<ImageReaderEngine>(find.byType(ImageReaderEngine))
                    .capability
                as BlogImageReaderCapability;
        expect(capability.request.initialIndex, 1);
        expect(capability.content.items, hasLength(2));
        expect(
          capability.request.requests.first.cacheKey,
          ImageCacheKeys.blogInline(_url),
        );
        expect(
          capability.request.requests.first.ownerId,
          source == 'article'
              ? '11'
              : source == 'comment'
              ? '31'
              : 'preview',
        );
        expect(
          capability.request.requests.every(
            (request) => request.ownerType == ImageCacheOwnerType.blog,
          ),
          isTrue,
        );
        expect(
          host.preload.specs.every(
            (spec) => spec.kind == ForumImageKind.blogInline,
          ),
          isTrue,
        );
        expect(host.details.queries, hasLength(source == 'preview' ? 0 : 1));
        host.navigator.currentState!.pop();
        await _frames(tester);
        expect(find.byType(BlogImageReaderPage), findsNothing);
        expect(tester.getTopLeft(target), before);
        expect(host.details.queries, hasLength(source == 'preview' ? 0 : 1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'account switch clears the reader and cannot revive it after switching back',
    (tester) async {
      final host = _Host();
      await host.pump(tester, 'article');
      final target = find.byKey(
        const Key('thread-post-html-first-readable-image-profile-blog-11-0'),
      );
      await tester.ensureVisible(target);
      final staleTap = tester.widget<GestureDetector>(target).onTap!;
      await _tapImage(tester, target);
      await _frames(tester);
      expect(find.byType(ImageReaderEngine), findsOneWidget);
      host.changeActor('202');
      await _frames(tester);
      expect(find.byType(ImageReaderEngine), findsNothing);
      host.changeActor('101');
      await _frames(tester);
      expect(find.byType(ImageReaderEngine), findsNothing);
      host.navigator.currentState!.pop();
      await _frames(tester);
      staleTap();
      await _frames(tester);
      expect(find.byType(BlogImageReaderPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'late reader preparation after leaving cannot replace the article',
    (tester) async {
      final host = _Host();
      final gate = Completer<ForumImagePrecacheResult>();
      host.preload.pending = gate;
      await host.pump(tester, 'article');
      final target = find.byKey(
        const Key('thread-post-html-first-readable-image-profile-blog-11-0'),
      );
      await tester.ensureVisible(target);
      await _tapImage(tester, target);
      await _frames(tester);
      expect(host.preload.specs, isNotEmpty);
      host.navigator.currentState!.pop();
      await _frames(tester);
      gate.complete(const ForumImagePrecacheResult(success: false));
      await _frames(tester);
      expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
      expect(find.byType(ImageReaderEngine), findsNothing);
      expect(host.details.queries, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

String _sourceId(String source) => switch (source) {
  'article' => 'profile-blog-11',
  'comment' => 'profile-blog-comment-31',
  _ => 'blog-editor-preview-preview',
};

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 32));
}

Future<void> _tapImage(WidgetTester tester, Finder image) async {
  // A failed image keeps its own central retry button. Tap the surrounding
  // image surface, as opposed to invoking retry or calling its callback.
  await tester.tapAt(tester.getTopLeft(image) + const Offset(8, 8));
  await _frames(tester);
}

final class _Host {
  final details = BlogDetailFixture();
  final preload = _Preload();
  final cache = _Cache();
  final navigator = GlobalKey<NavigatorState>();
  late final container = ProviderContainer(
    overrides: [
      blogAccountIdProvider.overrideWithValue('101'),
      userBlogDetailRepositoryProvider.overrideWithValue(details),
      forumImageRefererProvider.overrideWithValue('https://example.test/'),
      imageCacheServiceProvider.overrideWithValue(cache),
      forumImagePrecacheServiceProvider.overrideWithValue(preload),
      forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
        BlogVisualPreferences(),
      ),
    ],
  );

  void changeActor(String actor) => container.updateOverrides([
    blogAccountIdProvider.overrideWithValue(actor),
    userBlogDetailRepositoryProvider.overrideWithValue(details),
    forumImageRefererProvider.overrideWithValue('https://example.test/'),
    imageCacheServiceProvider.overrideWithValue(cache),
    forumImagePrecacheServiceProvider.overrideWithValue(preload),
    forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
      BlogVisualPreferences(),
    ),
  ]);

  Future<void> pump(WidgetTester tester, String source) async {
    addTearDown(container.dispose);
    if (source == 'article') details.bodyHtml = _html;
    if (source == 'comment') details.commentHtml = _html;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          navigatorKey: navigator,
          home: source == 'preview'
              ? const Scaffold(
                  body: SingleChildScrollView(
                    child: BlogEditorPreview(
                      draft: BlogEditorDraft(subject: 'draft', bodyHtml: _html),
                      ownerId: 'preview',
                    ),
                  ),
                )
              : const ProfileBlogDetailPage(ownerUserId: '101', blogId: '11'),
        ),
      ),
    );
    await _frames(tester);
  }
}

final class _Cache implements ImageCacheService {
  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async =>
      CachedImageResult(success: false, cacheKey: request.cacheKey);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Preload implements ForumImagePrecacheService {
  final specs = <ForumImageLoadSpec>[];
  Completer<ForumImagePrecacheResult>? pending;
  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(ForumImageLoadSpec spec) {
    specs.add(spec);
    return pending?.future ??
        Future.value(const ForumImagePrecacheResult(success: false));
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) => ensureDiskCached(spec);
}
