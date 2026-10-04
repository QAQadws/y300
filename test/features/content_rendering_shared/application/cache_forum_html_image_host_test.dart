import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/content_rendering_shared/application/host/cache_forum_html_image_host.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../../test_support/localized_test_app.dart';
import '../../thread/presentation/html_rendering/forum_html_test_theme.dart';

void main() {
  test(
    'display classification stays separate from preparation and referer',
    () {
      const referer = 'https://bbs.yamibo.com/thread-100-1-1.html';
      final base = CacheForumHtmlImageHost(dimensionIndex: _NoDimensions());
      final threadHost = base.forContent(
        threadId: '100',
        imageCacheOwnerId: ' chosen-owner ',
        imageReferer: referer,
      );
      final blogHost = base.forContent(
        threadId: '100',
        imageCacheOwnerId: ' chosen-owner ',
        imageReferer: referer,
        contentImageKind: ForumImageKind.blogInline,
      );
      final thread = threadHost.resolveImage(
        url: _source,
        imageIndex: 2,
        isSticker: false,
        htmlSize: const Size(600, 400),
      )!;
      final blog = blogHost.resolveImage(
        url: _source,
        imageIndex: 2,
        isSticker: false,
      )!;
      final sticker = blogHost.resolveImage(
        url: Uri.parse(
          'https://bbs.yamibo.com/static/image/smiley/default/smile.gif',
        ),
        imageIndex: 2,
        isSticker: true,
        htmlSize: const Size(30, 20),
      )!;

      expect(thread.request.ownerType, ImageCacheOwnerType.thread);
      expect(thread.request.role, ImageCacheRole.threadInline);
      expect(thread.request.ownerId, 'chosen-owner');
      expect(blog.request.ownerType, ImageCacheOwnerType.blog);
      expect(blog.request.role, ImageCacheRole.blogInline);
      expect(blog.request.ownerId, 'chosen-owner');
      expect(sticker.request.ownerType, ImageCacheOwnerType.sticker);
      expect(sticker.request.role, ImageCacheRole.remoteSmiley);
      expect(sticker.request.ownerId, 'yamibo-smiley-v4');
      expect(sticker.request.imageIndex, isNull);
      expect(sticker.request.retentionClass, ImageRetentionClass.sticky);

      final prepared = const DefaultForumHtmlRenderPreparer().prepare(
        html: '<img src="$_source">',
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: forumHtmlTestTheme,
        sourceId: 'article',
        threadId: '100',
        imageCacheOwnerId: 'chosen-owner',
      );
      expect(prepared.sequence.entries.single.cacheKey, thread.cacheKey);
      expect(blog.cacheKey, isNot(prepared.sequence.entries.single.cacheKey));

      final blockWidget =
          threadHost.buildImage(
                image: thread,
                fit: BoxFit.fitWidth,
                placeholder: const SizedBox.shrink(),
                waitForCacheWrite: true,
                showDelayedLoadingIndicator: true,
                onRetry: () {},
              )
              as CachedLibraryImage;
      final stickerWidget =
          blogHost.buildImage(
                image: sticker,
                fit: BoxFit.contain,
                width: sticker.initialLayout.displaySize?.width,
                height: sticker.initialLayout.displaySize?.height,
                placeholder: const SizedBox.shrink(),
              )
              as CachedLibraryImage;
      expect(blockWidget.request, same(thread.request));
      expect(stickerWidget.request, same(sticker.request));
      expect(blockWidget.referer, referer);
      expect(stickerWidget.referer, referer);
      expect(thread.spec.referer, isNull);
      expect(thread.request.referer, isNull);
      expect(
        blockWidget.remoteDisplayPolicy,
        CachedImageRemoteDisplayPolicy.afterCacheWrite,
      );
      expect(
        stickerWidget.remoteDisplayPolicy,
        CachedImageRemoteDisplayPolicy.eager,
      );
      expect(blockWidget.showDelayedLoadingIndicator, isTrue);
      expect(stickerWidget.showDelayedLoadingIndicator, isFalse);
      expect(stickerWidget.width, 30);
      expect(stickerWidget.height, 20);
    },
  );

  test(
    'scoped disk work observes cancellation without starting decode',
    () async {
      final service = _ScopedDiskPrecache();
      final host = CacheForumHtmlImageHost(
        dimensionIndex: _NoDimensions(),
      ).forContent(threadId: '100', imagePrecacheService: service);
      final image = host.resolveImage(
        url: _source,
        imageIndex: 0,
        isSticker: false,
      )!;
      final token = ForumHtmlImageWorkToken();
      final operation = host.prefetchDisk(image, scope: token);
      expect(service.scopes, hasLength(1));
      expect(service.specs.single, same(image.spec));
      expect(service.scopes.single.isActive, isTrue);

      token.cancel();
      expect(service.scopes.single.isActive, isFalse);
      await host.prefetchDisk(image, scope: token);
      expect(service.scopes, hasLength(1));

      service.pending.complete(const ForumImagePrecacheResult(success: true));
      await operation;
      expect(service.legacyCalls, 0);
      expect(service.decodeCalls, 0);
      expect(service.scopes.single.isActive, isFalse);
    },
  );

  testWidgets(
    'transport URL changes preserve DOM taps and update work identity',
    (tester) async {
      CacheForumHtmlImageHost cacheHost(String transportUrl) =>
          CacheForumHtmlImageHost(dimensionIndex: _NoDimensions()).forContent(
            threadId: '100',
            imageRequestResolver: _TransportUrlResolver(transportUrl),
          );
      final host = cacheHost('https://images.example/a.jpg');
      final first = host.resolveImage(
        url: _source,
        imageIndex: 0,
        isSticker: false,
      )!;
      final equal = host.resolveImage(
        url: _source,
        imageIndex: 0,
        isSticker: false,
      )!;
      final replacement = cacheHost(
        'https://images.example/b.jpg',
      ).resolveImage(url: _source, imageIndex: 0, isSticker: false)!;
      expect(first.sourceUrl, _source.toString());
      expect(first.request.sourceUrl, 'https://images.example/a.jpg');
      expect(first.cacheKey, replacement.cacheKey);
      expect(first.identity, equal.identity);
      expect(first, isNot(same(equal)));
      expect(first.identity, isNot(replacement.identity));

      ForumHtmlImageRequest? tapped;
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              sourceId: 'transport-projection',
              theme: forumHtmlTestTheme,
              html: '<img src="$_source" width="200" height="100">',
              buildAsync: false,
              imageHost: _ProjectionOnlyHost(host),
              callbacks: ForumHtmlRenderCallbacks(
                onTapImage: (image) => tapped = image,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const Key(
            'thread-post-html-first-readable-image-transport-projection-0',
          ),
        ),
      );
      expect(tapped?.url, _source.toString());
      expect(tapped?.cacheKey, first.cacheKey);
      expect(tapped?.readableIndex, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

final _source = Uri.parse(
  'https://bbs.yamibo.com/data/attachment/forum/page.jpg',
);

final class _NoDimensions implements ForumImageDimensionIndex {
  @override
  Future<ForumImageDimensions?> getBySpec(ForumImageLoadSpec spec) async =>
      null;

  @override
  Future<ForumImageDimensions?> getLastKnownBySpec(
    ForumImageLoadSpec spec,
  ) async => null;

  @override
  Future<void> recordDecodedDimensions({
    required ForumImageLoadSpec spec,
    required Size size,
  }) async {}
}

final class _ScopedDiskPrecache
    implements ForumImagePrecacheService, ScopedForumImagePrecacheService {
  final pending = Completer<ForumImagePrecacheResult>();
  final specs = <ForumImageLoadSpec>[];
  final scopes = <ForumImageWorkScope>[];
  int legacyCalls = 0;
  int decodeCalls = 0;

  @override
  Future<ForumImagePrecacheResult> ensureDiskCachedScoped(
    ForumImageLoadSpec spec, {
    required ForumImageWorkScope scope,
  }) {
    specs.add(spec);
    scopes.add(scope);
    return pending.future;
  }

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(ForumImageLoadSpec spec) {
    legacyCalls++;
    return pending.future;
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async {
    decodeCalls++;
    return const ForumImagePrecacheResult(success: false);
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecodedScoped({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    required ForumImageWorkScope scope,
    Size? expectedDisplaySize,
  }) => precacheDecoded(
    context: context,
    spec: spec,
    expectedDisplaySize: expectedDisplaySize,
  );
}

final class _TransportUrlResolver implements ForumImageRequestResolver {
  const _TransportUrlResolver(this.transportUrl);
  final String transportUrl;

  @override
  ImageCacheRequest resolveCacheRequest(ForumImageLoadSpec spec) =>
      ImageCacheRequest(
        cacheKey: 'transport-cache-key',
        sourceUrl: transportUrl,
        ownerType: ImageCacheOwnerType.thread,
        ownerId: '100',
        role: ImageCacheRole.threadInline,
      );

  @override
  ForumImageRenderPolicy resolveRenderPolicy(ForumImageLoadSpec spec) =>
      const DefaultForumImageRequestResolver().resolveRenderPolicy(spec);
}

/// Exercises the real factory/tap mapping without starting cache I/O.
final class _ProjectionOnlyHost implements ForumHtmlImageHost {
  const _ProjectionOnlyHost(this.delegate);
  final CacheForumHtmlImageHost delegate;

  @override
  ForumHtmlDisplayImage? resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => delegate.resolveImage(
    url: url,
    imageIndex: imageIndex,
    isSticker: isSticker,
    htmlSize: htmlSize,
  );

  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) => delegate.loadDimensions(image);

  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) =>
      delegate.onBlockImageResolved(image, size);

  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) => delegate.prefetchDisk(image, scope: scope);

  @override
  Widget buildImage({
    required ForumHtmlDisplayImage image,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    VoidCallback? onRetry,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) => placeholder;
}
