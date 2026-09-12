import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/media/image_display_provider.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_surface.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_comment_fixture.dart';
import '../test_support/blog_operation_fixture.dart';
import '../test_support/blog_visual_fixture.dart';

const _output = String.fromEnvironment('BLOG_VISUAL_OUTPUT');
const _font = String.fromEnvironment('BLOG_VISUAL_FONT');
const _capture = Key('blog-visual-capture');

void main() {
  setUpAll(() async {
    if (_output.isEmpty) return;
    if (_font.isNotEmpty) {
      await (FontLoader(
        'BlogVisual',
      )..addFont(File(_font).readAsBytes().then(ByteData.sublistView))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final family in AppThemeFamily.values) {
    for (final brightness in Brightness.values) {
      for (final compact in [false, true]) {
        final name =
            '${family.name}-${brightness.name}-${compact ? 'large' : 'normal'}';
        testWidgets('$name keeps reading surfaces, links and inputs usable', (
          tester,
        ) async {
          final host = _Host(
            AppTheme.build(family: family, brightness: brightness),
            compact,
          );
          await host.pump(tester, const ProfileBlogPage());
          final l10n = AppLocalizations.of(
            tester.element(find.byType(ProfileBlogPage)),
          );
          _checkSurfaces(tester, host.theme);
          final title = tester.widget<Text>(find.text(blogVisualTitle));
          expect(title.style!.color, host.theme.y300NativeContent.itemTitle);
          final tabs = find.byKey(const Key('profile-blog-view-tabs'));
          expect(tester.getSize(tabs).height, greaterThanOrEqualTo(48));
          expect(
            find.descendant(of: tabs, matching: find.byType(AnimatedContainer)),
            findsNothing,
          );
          expect(find.text(l10n.profileBlogTitle), findsOneWidget);
          await _save(tester, '$name-list');

          await tester.tap(find.byKey(const Key('profile-blog-item-11')));
          await tester.pumpAndSettle();
          expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
          _checkSurfaces(tester, host.theme);
          for (final view in tester.widgetList<ForumHtmlContentView>(
            find.byType(ForumHtmlContentView),
          )) {
            expect(view.surfaceColor, host.theme.y300NativeContent.card);
            expect(view.foregroundColor, host.theme.y300NativeContent.body);
          }
          await _save(tester, '$name-article');
          final heading = find.byKey(
            const Key('profile-blog-comments-heading'),
          );
          await tester.scrollUntilVisible(
            heading,
            200,
            scrollable: find
                .descendant(
                  of: find.byKey(const Key('profile-blog-detail')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await _save(tester, '$name-comments');
          expect(tester.takeException(), isNull);

          await host.pump(
            tester,
            BlogCommentPage(
              target: blogCommentTarget(UserBlogCommentAction.add),
            ),
            keyboard: true,
          );
          final input = find.byKey(const Key('blog-comment-input'));
          await tester.enterText(input, '这一段评论仍然可以编辑。');
          final submit = find.byKey(const Key('blog-comment-submit'));
          await tester.ensureVisible(submit);
          await tester.pumpAndSettle();
          expect(
            tester.getBottomRight(submit).dy,
            lessThanOrEqualTo(844 - 260),
          );
          expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
          expect(tester.widget<TextField>(input).decoration!.border, isNull);
          await _save(tester, '$name-comment-input');

          await host.pump(
            tester,
            BlogEditorPage(target: blogActionTarget(UserBlogAction.edit)),
            keyboard: true,
          );
          final subject = find.byKey(const Key('blog-editor-subject'));
          await tester.enterText(subject, blogVisualTitle);
          expect(tester.widget<TextField>(subject).decoration!.border, isNull);
          await _save(tester, '$name-editor');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final state in ['loading', 'empty', 'error', 'login']) {
    testWidgets('$state stays within a narrow large-text viewport', (
      tester,
    ) async {
      final host = _Host(AppTheme.dark(), true);
      final pending = Completer<void>();
      host.directory
        ..empty = state == 'empty'
        ..gate = state == 'loading' ? pending : null
        ..failure = switch (state) {
          'error' => DataReadFailureKind.network,
          'login' => DataReadFailureKind.unauthorized,
          _ => null,
        };
      await host.pump(
        tester,
        const ProfileBlogPage(),
        settle: state != 'loading',
      );
      if (state == 'loading') {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
      if (state == 'error' || state == 'login') {
        expect(find.byKey(const Key('blog-read-open-web')), findsOneWidget);
      }
      await _save(tester, state);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      if (state == 'loading') pending.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a real local article image renders inside the native surface', (
    tester,
  ) async {
    final host = _Host(AppTheme.light(), false);
    host.details.withImage = true;
    await host.pump(
      tester,
      const ProfileBlogDetailPage(ownerUserId: '101', blogId: '11'),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final picture = find.byWidgetPredicate(
      (widget) => widget is CachedLibraryImage && widget.request != null,
    );
    await tester.ensureVisible(picture);
    await tester.pump(const Duration(milliseconds: 500));
    final file = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('blog-visual-');
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xFFE4F0E6), BlendMode.src);
      canvas.drawRect(
        const Rect.fromLTWH(0, 75, 240, 25),
        Paint()..color = const Color(0xFF618563),
      );
      canvas.drawCircle(
        const Offset(60, 45),
        25,
        Paint()..color = const Color(0xFF8AA876),
      );
      canvas.drawCircle(
        const Offset(175, 24),
        12,
        Paint()..color = const Color(0xFFE5C981),
      );
      final recording = recorder.endRecording();
      final frame = await recording.toImage(240, 100);
      try {
        final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
        return File(
          '${directory.path}/fixture.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        frame.dispose();
        recording.dispose();
      }
    });
    addTearDown(() => file!.parent.delete(recursive: true));
    final widget = tester.widget<CachedLibraryImage>(picture);
    final provider = resolveDownscaledFileImageProvider(
      localPath: file!.path,
      fit: widget.fit,
      displaySize: tester.getSize(picture),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(tester.element(picture)),
    );
    addTearDown(provider.evict);
    await tester.runAsync(
      () => precacheImage(provider, tester.element(picture)),
    );
    host.cache.result.complete(
      CachedImageResult(
        success: true,
        cacheKey: host.cache.keys.first,
        localPath: file.path,
        width: 240,
        height: 100,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RawImage && widget.image?.width == 240,
      ),
      findsOneWidget,
    );
    await _save(tester, 'article-image');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _checkSurfaces(WidgetTester tester, ThemeData theme) {
  final cards = find.byType(BlogSurface);
  expect(cards, findsWidgets);
  for (final card in cards.evaluate()) {
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byElementPredicate(
                          (element) => element == card,
                        ),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(
      decoration.boxShadow,
      ForumNativeSurfaceShadows.card(theme.y300NativeContent.stateLayer),
    );
    expect(decoration.border, isNull);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byElementPredicate((element) => element == card),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.elevation, 0);
    expect(material.color, theme.y300NativeContent.card);
    expect(material.clipBehavior, Clip.antiAlias);
  }
}

Future<void> _save(WidgetTester tester, String name) async {
  if (_output.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  final shadows = debugDisableShadows;
  try {
    debugDisableShadows = false;
    _repaint(boundary);
    await tester.pump();
    await tester.runAsync(() async {
      final frame = await boundary.toImage();
      try {
        final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
        final directory = await Directory(_output).create(recursive: true);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        frame.dispose();
      }
    });
  } finally {
    debugDisableShadows = shadows;
    _repaint(boundary);
    await tester.pump();
  }
}

void _repaint(RenderObject object) {
  object.markNeedsPaint();
  object.visitChildren(_repaint);
}

final class _Host {
  _Host(this.theme, this.compact);
  final ThemeData theme;
  final bool compact;
  final directory = BlogVisualDirectory();
  final details = BlogVisualDetail();
  final cache = _Images();

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    bool keyboard = false,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(compact ? 300 : 390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          blogAccountIdProvider.overrideWithValue('101'),
          userBlogDirectoryRepositoryProvider.overrideWithValue(directory),
          userBlogDetailRepositoryProvider.overrideWithValue(details),
          userBlogOperationsProvider.overrideWithValue(
            BlogOperationFixture(autoPrepare: true),
          ),
          userBlogCommentServiceProvider.overrideWithValue(
            BlogCommentFixture(autoPrepare: true),
          ),
          forumImageRefererProvider.overrideWithValue('https://example.test/'),
          imageCacheServiceProvider.overrideWithValue(cache),
          appServerContentConversionModeProvider.overrideWithValue(
            TextConversionMode.none,
          ),
          forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
            BlogVisualPreferences(),
          ),
        ],
        child: RepaintBoundary(
          key: _capture,
          child: LocalizedTestApp(
            debugShowCheckedModeBanner: false,
            theme: _font.isEmpty
                ? theme
                : theme.copyWith(
                    textTheme: theme.textTheme.apply(fontFamily: 'BlogVisual'),
                    // ChipTheme supplies its own label styles instead of
                    // inheriting the application's text theme font family.
                    chipTheme: theme.chipTheme.copyWith(
                      labelStyle: theme.chipTheme.labelStyle?.copyWith(
                        fontFamily: 'BlogVisual',
                      ),
                      secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle
                          ?.copyWith(fontFamily: 'BlogVisual'),
                    ),
                  ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(compact ? 2 : 1),
                disableAnimations: compact,
                viewInsets: EdgeInsets.only(bottom: keyboard ? 260 : 0),
              ),
              child: child!,
            ),
            home: page,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(forumDefaultAvatarAsset),
        tester.element(find.byType(Scaffold).first),
      ),
    );
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
  }
}

final class _Images implements ImageCacheService {
  final result = Completer<CachedImageResult>();
  final keys = <String>[];
  @override
  Future<CachedImageResult?> getCached(String cacheKey) {
    keys.add(cacheKey);
    return result.future;
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) =>
      throw StateError('Visual fixtures must never download an image');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
