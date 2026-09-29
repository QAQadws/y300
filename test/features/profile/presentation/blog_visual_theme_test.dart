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
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_theme_factory.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';
import 'package:y300/shared/widgets/forum_metric_pill.dart';
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

          final listScrollable = find.descendant(
            of: find.byKey(const Key('profile-blog-list')),
            matching: find.byType(Scrollable),
          );
          final pagination = find.byKey(const Key('profile-blog-pagination'));
          await tester.scrollUntilVisible(
            pagination,
            200,
            scrollable: listScrollable,
          );
          await tester.pumpAndSettle();
          expect(find.text(l10n.commonPage(1)), findsOneWidget);
          expect(find.text(l10n.forumDisplayNoMore), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _save(tester, '$name-pagination');
          await tester.scrollUntilVisible(
            find.text(blogVisualTitle),
            -200,
            scrollable: listScrollable,
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text(blogVisualTitle));
          await tester.pumpAndSettle();
          expect(find.byType(ProfileBlogDetailPage), findsOneWidget);
          _checkSurfaces(tester, host.theme);
          _checkHtmlTheme(tester, host.theme, sourceId: 'profile-blog-11');
          expect(find.byKey(const Key('blog-detail-open-web')), findsNothing);
          final views = find.byKey(const Key('blog-detail-views'));
          final commentCount = find.byKey(
            const Key('blog-detail-comment-count'),
          );
          final author = find.byKey(const Key('blog-detail-author'));
          final date = find.byKey(const Key('blog-detail-date'));
          final category = find.byKey(
            const ValueKey(
              UserBlogDirectoryQuery.self(
                ownerUserId: '101',
                personalCategoryId: '3',
              ),
            ),
          );
          expect(find.byIcon(Icons.folder_outlined), findsNothing);
          expect(
            tester.getTopLeft(category).dy,
            greaterThan(tester.getBottomRight(author).dy),
          );
          final palette = ThreadDetailNativePalette.resolve(host.theme);
          for (final metric in [views, commentCount]) {
            final pill = tester.widget<ForumMetricPill>(metric);
            expect(pill.backgroundColor, palette.chipBackground);
            expect(pill.iconColor, palette.softText);
            expect(pill.textColor, palette.muted);
          }
          if (compact) {
            expect(
              tester.getTopLeft(category).dy,
              greaterThan(tester.getBottomRight(date).dy),
            );
            expect(
              tester.getTopLeft(views).dy,
              greaterThan(tester.getBottomRight(author).dy),
            );
          } else {
            expect(
              tester.getCenter(category).dy,
              closeTo(tester.getCenter(date).dy, 1),
            );
            expect(
              tester.getTopLeft(views).dy,
              closeTo(tester.getTopLeft(author).dy, 1),
            );
            expect(
              tester.getTopLeft(views).dx,
              greaterThan(tester.getBottomRight(author).dx),
            );
          }
          expect(tester.takeException(), isNull);
          await _save(tester, '$name-article');
          expect(find.byKey(const Key('blog-detail-actions')), findsNothing);
          expect(find.byKey(const Key('blog-detail-reply')), findsOneWidget);
          final article = find.byKey(const Key('blog-detail-card'));
          await tester.longPressAt(
            tester.getTopLeft(article) + const Offset(20, 20),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('blog-content-action-sheet')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await _save(tester, '$name-article-actions');
          Navigator.of(
            tester.element(find.byKey(const Key('blog-content-action-sheet'))),
          ).pop();
          await tester.pumpAndSettle();
          final heading = find.byKey(
            const Key('profile-blog-comments-heading'),
          );
          final detailScrollable = find
              .descendant(
                of: find.byKey(const Key('profile-blog-detail')),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            heading,
            200,
            scrollable: detailScrollable,
          );
          await tester.pumpAndSettle();
          await _save(tester, '$name-comments');
          await tester.scrollUntilVisible(
            find.byKey(const Key('profile-blog-comment-31')),
            200,
            scrollable: detailScrollable,
          );
          await tester.pumpAndSettle();
          _checkHtmlTheme(
            tester,
            host.theme,
            sourceId: 'profile-blog-comment-31',
          );
          expect(
            find.byKey(const Key('blog-comment-actions-31')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('profile-blog-comment-button')),
            findsNothing,
          );
          final comment = find.byKey(const Key('profile-blog-comment-31'));
          await tester.longPressAt(
            tester.getTopLeft(comment) + const Offset(20, 3),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('blog-content-action-sheet')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('blog-content-action-reply')),
            findsOneWidget,
          );
          await _save(tester, '$name-comment-actions');
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
            const BlogEditorPage(
              target: UserBlogTarget(
                actorUserId: '101',
                ownerUserId: '101',
                action: UserBlogAction.create,
              ),
            ),
            keyboard: compact,
          );
          final subject = find.byKey(const Key('blog-editor-subject'));
          await tester.enterText(subject, blogVisualTitle);
          expect(
            tester.widget<TextField>(subject).decoration!.border,
            isA<UnderlineInputBorder>(),
          );
          await tester.enterText(
            find.byKey(const Key('blog-editor-body')),
            '记下今天想分享的事情。\n\n读完一本喜欢的书，也遇见了一些温柔的小事。',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await _save(tester, '$name-editor');
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('blog-editor-settings')));
          await tester.pumpAndSettle();
          final settings = find.byKey(const Key('blog-editor-settings-sheet'));
          expect(settings, findsOneWidget);
          await _save(tester, '$name-editor-settings');
          final settingsScroll = find
              .descendant(of: settings, matching: find.byType(Scrollable))
              .first;
          await tester.scrollUntilVisible(
            find.byKey(const Key('blog-editor-open-web')),
            200,
            scrollable: settingsScroll,
          );
          await tester.pumpAndSettle();
          await _save(tester, '$name-editor-settings-options');
          expect(tester.takeException(), isNull);
          for (final (label, key, value, snapshot) in [
            (
              l10n.profileBlogVisibilityPassword,
              'blog-editor-password',
              'private-reading-2026',
              'password',
            ),
            (
              l10n.profileBlogVisibilitySelected,
              'blog-editor-target-names',
              'Alice Bob\n一起读书的朋友 长用户名的朋友',
              'selected-friends',
            ),
          ]) {
            final visibility = find.byKey(const Key('blog-editor-visibility'));
            await tester.ensureVisible(visibility);
            await tester.tap(visibility);
            await tester.pumpAndSettle();
            final choice = find.text(label).last;
            await tester.ensureVisible(choice);
            await tester.tap(choice);
            await tester.pumpAndSettle();
            final accessInput = find.byKey(Key(key));
            await tester.ensureVisible(accessInput);
            await tester.enterText(accessInput, value);
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await tester.ensureVisible(accessInput);
            await tester.pumpAndSettle();
            expect(accessInput.hitTestable(), findsOneWidget);
            final accessField = tester.widget<TextField>(accessInput);
            expect(accessField.controller!.text, value);
            expect(accessField.readOnly, isFalse);
            expect(accessField.obscureText, snapshot == 'password');
            final bounds = tester.getRect(accessInput);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(compact ? 300 : 390));
            expect(bounds.bottom, lessThanOrEqualTo(compact ? 844 - 260 : 844));
            expect(tester.takeException(), isNull);
            await _save(tester, '$name-editor-settings-$snapshot');
          }
          final settingsDone = find.byKey(
            const Key('blog-editor-settings-done'),
          );
          await tester.ensureVisible(settingsDone);
          await tester.tap(settingsDone);
          await tester.pumpAndSettle();

          host.directory.categories = const [
            UserBlogCategory(id: '1', name: '正能量'),
            UserBlogCategory(id: '2', name: '倒黑泥'),
            UserBlogCategory(id: '3', name: '日常与阅读'),
            UserBlogCategory(id: '4', name: '旅行见闻'),
            UserBlogCategory(id: '5', name: '从电影和书籍里得到的零碎灵感'),
            UserBlogCategory(id: '6', name: '绘画练习'),
            UserBlogCategory(id: '7', name: '游戏记录'),
            UserBlogCategory(id: '8', name: '其他'),
          ];
          await host.pump(
            tester,
            const ProfileBlogPage(
              initialScope: UserBlogFeedScope.self,
              ownerUserId: '101',
              initialPersonalCategoryId: '1',
            ),
          );
          final categoryTabs = find.byKey(
            const Key('profile-blog-category-tabs'),
          );
          expect(categoryTabs, findsOneWidget);
          expect(
            find.byKey(const Key('profile-blog-category-1')).hitTestable(),
            findsOneWidget,
          );
          await _save(tester, '$name-categories');
          await tester.drag(categoryTabs, const Offset(-180, 0));
          await tester.pumpAndSettle();
          await _save(tester, '$name-categories-scrolled');
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

void _checkHtmlTheme(
  WidgetTester tester,
  ThemeData theme, {
  required String sourceId,
}) {
  final renderer = tester.widget<ForumHtmlWidgetPostRenderer>(
    find.byWidgetPredicate(
      (widget) =>
          widget is ForumHtmlWidgetPostRenderer && widget.sourceId == sourceId,
    ),
  );
  final postTheme = const ForumHtmlRenderThemeFactory().fromThreadPalette(
    palette: ThreadDetailNativePalette.resolve(theme),
    brightness: theme.brightness,
  );
  expect(renderer.theme.signature, postTheme.signature);
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
