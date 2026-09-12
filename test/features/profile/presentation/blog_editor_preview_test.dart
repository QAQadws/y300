import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_preview.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';

import '../../../test_support/localized_test_app.dart';

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
      final renderer = tester.widget<ForumHtmlWidgetPostRenderer>(
        find.byType(ForumHtmlWidgetPostRenderer),
      );
      expect(renderer.preferences, preferences);
      expect(renderer.html, '<h2>Title &lt;literal&gt;</h2>${draft.bodyHtml}');
      final view = tester.widget<ForumHtmlContentView>(
        find.byType(ForumHtmlContentView),
      );
      expect(view.foregroundColor, theme.y300NativeContent.body);
      expect(view.surfaceColor, theme.y300NativeContent.card);
      expect(repository.saves, 0);
      expect(tester.takeException(), isNull);
    },
  );
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
