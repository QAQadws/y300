import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_author_color_parser.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  testWidgets(
    'prepares shared HTML once per content theme and preference identity',
    (tester) async {
      final preparer = _CountingRenderPreparer();
      final repository = _FixedPreferencesRepository(
        ForumHtmlReaderPreferences.defaults(),
      );

      await tester.pumpWidget(
        _host(
          theme: ThemeData.dark(useMaterial3: true),
          repository: repository,
          preparer: preparer,
        ),
      );
      await tester.pumpAndSettle();

      expect(preparer.callCount, 1);
      final darkHtml = tester
          .widget<HtmlWidget>(
            find.byKey(const Key('forum-html-renderer-shared-content')),
          )
          .html;
      final darkText = const CsslibAuthorColorParser().parseOwn(
        html_parser.parseFragment(darkHtml).querySelector('#body')!,
      );
      expect(darkText.foreground?.toARGB32(), isNot(0xFF000000));

      await tester.pumpWidget(
        _host(
          theme: ThemeData.dark(useMaterial3: true),
          repository: repository,
          preparer: preparer,
        ),
      );
      await tester.pumpAndSettle();
      expect(preparer.callCount, 1);

      await tester.pumpWidget(
        _host(
          theme: ThemeData.light(useMaterial3: true),
          repository: repository,
          preparer: preparer,
        ),
      );
      await tester.pumpAndSettle();

      expect(preparer.callCount, 2);
      final lightHtml = tester
          .widget<HtmlWidget>(
            find.byKey(const Key('forum-html-renderer-shared-content')),
          )
          .html;
      final lightText = const CsslibAuthorColorParser().parseOwn(
        html_parser.parseFragment(lightHtml).querySelector('#body')!,
      );
      expect(lightText.foreground?.toARGB32(), 0xFF000000);
      expect(lightHtml, isNot(darkHtml));
    },
  );
}

Widget _host({
  required ThemeData theme,
  required ForumHtmlReaderPreferencesRepository repository,
  required ForumHtmlRenderPreparer preparer,
}) {
  return ProviderScope(
    overrides: [
      forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
        repository,
      ),
    ],
    child: MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: ForumHtmlContentView(
          html: '<font id="body" color="black">共享正文</font>',
          sourceId: 'shared-content',
          renderPreparer: preparer,
        ),
      ),
    ),
  );
}

final class _CountingRenderPreparer implements ForumHtmlRenderPreparer {
  final _delegate = const DefaultForumHtmlRenderPreparer();
  int callCount = 0;

  @override
  ForumHtmlPreparedRenderDocument prepare({
    required String html,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  }) {
    callCount++;
    return _delegate.prepare(
      html: html,
      preferences: preferences,
      theme: theme,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
    );
  }
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
