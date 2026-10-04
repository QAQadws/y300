import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/content_rendering/native_forum_html_render_theme_factory.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/reader_shared/presentation/rich_text/color/rich_text_tone_resolver.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('native $brightness rendering keeps the complete post palette', () {
      final base = brightness == Brightness.dark
          ? AppTheme.dark()
          : AppTheme.light();
      final theme = base.copyWith(
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: const Color(0xFF264B73),
        ),
      );
      final palette = ThreadDetailNativePalette.resolve(theme);
      final surface = _opaque(palette.card, palette.background);
      final foreground = _opaque(palette.bodyText, surface);
      final expected = ForumHtmlThemeContext(
        brightness: brightness == Brightness.dark
            ? ForumHtmlBrightness.dark
            : ForumHtmlBrightness.light,
        surface: surface,
        foreground: foreground,
        link: const MaterialRichTextToneResolver().resolveReadableForeground(
          requested: palette.accent,
          background: surface,
          fallback: foreground,
          minimumContrast:
              ForumHtmlColorAdaptationPolicy.standard.minimumTextContrast,
        ),
        quoteSurface: _opaque(palette.panelBackground, surface),
        quoteForeground: foreground,
        codeSurface: _opaque(palette.cardElevated, surface),
        codeForeground: foreground,
      );

      final actual = const ForumHtmlRenderThemeFactory().fromNativeTheme(
        theme: theme,
      );

      expect(actual.signature, expected.signature);
    });
  }

  test(
    'default preparation preserves legacy thread ownership for every source',
    () {
      const preparer = DefaultForumHtmlRenderPreparer();
      const resolver = DefaultForumImageRequestResolver();
      final theme = _renderTheme();
      for (final owner in <({String? tid, String? override, String expected})>[
        (tid: ' 100 ', override: null, expected: '100'),
        (
          tid: '100',
          override: ' novel-chapter-owner ',
          expected: 'novel-chapter-owner',
        ),
        (tid: null, override: ' ', expected: 'unknown'),
      ]) {
        final document = preparer.prepare(
          html:
              '<img src="https://example.invalid/page.jpg" width="200" height="300">',
          preferences: ForumHtmlReaderPreferences.defaults(),
          theme: theme,
          sourceId: 'novel-chapter-snapshot',
          threadId: owner.tid,
          imageCacheOwnerId: owner.override,
        );
        final image = document.sequence.entries.single;
        final request = resolver.resolveCacheRequest(image.spec)!;

        expect(image.spec.kind, ForumImageKind.threadInline);
        expect(image.spec.ownerType, ImageCacheOwnerType.thread);
        expect(image.spec.ownerId, owner.expected);
        expect(image.spec.allowReaderOpen, isTrue);
        expect(request.ownerId, owner.expected);
        expect(request.role, ImageCacheRole.threadInline);
        expect(request.effectiveRetentionClass, ImageRetentionClass.ephemeral);
        expect(image.cacheKey, request.cacheKey);
      }
    },
  );

  test(
    'Host image policy survives document projection and later cache resolution',
    () {
      const preparer = DefaultForumHtmlRenderPreparer(
        imagePolicy: _ProtectedNovelImagePolicy(),
      );
      final document = preparer.prepare(
        html:
            '<img src="https://example.invalid/host-page.jpg" width="200" height="300">',
        preferences: ForumHtmlReaderPreferences.defaults(),
        theme: _renderTheme(),
        sourceId: 'host-chapter',
        threadId: 'legacy-thread',
        imageCacheOwnerId: 'legacy-owner',
      );
      final image = document.sequence.entries.single;
      final spec = image.spec;
      final request = const DefaultForumImageRequestResolver()
          .resolveCacheRequest(spec)!;

      expect(spec.kind, ForumImageKind.comicReaderPage);
      expect(spec.ownerType, ImageCacheOwnerType.novel);
      expect(spec.ownerId, 'novel-host-owner');
      expect(spec.episodeId, 'chapter-host');
      expect(spec.referer, 'https://example.invalid/novel');
      expect(spec.displayWidth, 400);
      expect(spec.displayHeight, 600);
      expect(spec.protected, isTrue);
      expect(spec.allowReaderOpen, isFalse);
      expect(spec.retentionClass, ImageRetentionClass.protected);
      expect(image.cacheKey, 'host-content:0');
      expect(request.ownerType, ImageCacheOwnerType.novel);
      expect(request.ownerId, spec.ownerId);
      expect(request.episodeId, spec.episodeId);
      expect(request.referer, spec.referer);
      expect(request.protected, isTrue);
      expect(request.effectiveRetentionClass, ImageRetentionClass.protected);
    },
  );
}

Color _opaque(Color color, Color background) =>
    (color.toARGB32() >>> 24) == 0xFF
    ? color
    : Color.alphaBlend(color, background);

ForumHtmlThemeContext _renderTheme() =>
    const ForumHtmlRenderThemeFactory().fromMaterialTheme(
      theme: AppTheme.light(),
      surface: const Color(0xFFFFFFFF),
    );

class _ProtectedNovelImagePolicy implements ForumHtmlPreparationImagePolicy {
  const _ProtectedNovelImagePolicy();

  @override
  ForumImageLoadSpec inlineSpec({
    required Uri url,
    required String? threadId,
    required String? imageCacheOwnerId,
    required int imageIndex,
    double? htmlWidth,
    double? htmlHeight,
    String? alt,
    String? title,
  }) => ForumImageLoadSpec(
    kind: ForumImageKind.comicReaderPage,
    url: url,
    referer: 'https://example.invalid/novel',
    ownerType: ImageCacheOwnerType.novel,
    ownerId: 'novel-host-owner',
    episodeId: 'chapter-host',
    imageIndex: imageIndex,
    cacheKey: 'host-content:$imageIndex',
    retentionClass: ImageRetentionClass.protected,
    htmlWidth: htmlWidth,
    htmlHeight: htmlHeight,
    displayWidth: 400,
    displayHeight: 600,
    alt: alt,
    title: title,
    protected: true,
    allowReaderOpen: false,
  );
}
