import 'package:y300/app/content_rendering/native_forum_html_render_theme_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_preview.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:y300/features/profile/presentation/blog/blog_rich_text_embeds.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';

import '../../../test_support/localized_test_app.dart';
import '../../../test_support/native_body_finders.dart';

void main() {
  testWidgets(
    'preview follows reader typography and native theme without rewriting input',
    (tester) async {
      final defaults = ForumHtmlReaderPreferences.defaults();
      final preferences = defaults.copyWith(
        typography: defaults.typography.copyWith(
          fontScale: 1.8,
          lineHeightScale: 2.1,
        ),
        preserveAuthorFontSize: false,
      );
      final repository = _Preferences(preferences);
      const draft = BlogEditorDraft(
        subject: 'Title <literal>',
        bodyHtml: '<p>繁體 &amp; <b>原文</b></p>',
      );
      final theme = AppTheme.dark();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumImageRefererProvider.overrideWithValue(
              'https://example.test/',
            ),
            forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
              repository,
            ),
          ],
          child: LocalizedTestApp(
            theme: theme,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: BlogEditorPreview(
                  draft: draft,
                  ownerId: 'preview-fixture',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final renderer = tester.widget<ForumNativeBodyFlow>(
        findNativeBody('blog-editor-preview-preview-fixture'),
      );
      expect(renderer.preferences, preferences);
      expect(
        tester
            .widget<ForumHtmlContentView>(find.byType(ForumHtmlContentView))
            .html,
        '<h2>Title &lt;literal&gt;</h2>${draft.bodyHtml}',
      );
      expect(findNativeBodyText('Title <literal>'), findsOneWidget);
      expect(findNativeBodyText('繁體 & 原文'), findsOneWidget);
      final postTheme = const ForumHtmlRenderThemeFactory().fromThreadPalette(
        palette: ThreadDetailNativePalette.resolve(theme),
        brightness: theme.brightness,
      );
      expect(renderer.theme.signature, postTheme.signature);
      expect(repository.saves, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retained editor HTML renders ruby from the original payload', (
    tester,
  ) async {
    const original = '<p><ruby>書<rt>しょ</rt></ruby>を読む。</p>';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumImageRefererProvider.overrideWithValue('https://example.test/'),
          forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
            _Preferences(ForumHtmlReaderPreferences.defaults()),
          ),
        ],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: BlogPreservedHtml(html: original, id: 'ruby'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(findNativeBody('blog-editor-preserved-ruby'), findsOneWidget);
    expect(find.byType(ForumBodyInlineParagraphSurface), findsOneWidget);
    expect(
      tester.widget<BlogPreservedHtml>(find.byType(BlogPreservedHtml)).html,
      original,
    );
  });
}

final class _Preferences implements ForumHtmlReaderPreferencesRepository {
  _Preferences(this.value);
  final ForumHtmlReaderPreferences value;
  int saves = 0;
  @override
  Future<ForumHtmlReaderPreferences> load() async => value;
  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    saves++;
  }
}
