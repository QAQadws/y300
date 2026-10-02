import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_theme_factory.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('reuses prepared HTML and invalidates every preparation input', (
    tester,
  ) async {
    final repository = _PreferencesRepository();
    final container = ProviderContainer(
      overrides: [
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          repository,
        ),
      ],
    );
    addTearDown(container.dispose);
    final preparer = _CountingPreparer();
    var activePreparer = preparer;
    var html = '<p>body <b>bold</b></p><a href="https://example.test">link</a>';
    var pid = 'p1';
    var tid = '100';
    var theme = ThemeData.light();
    var callbackRevision = 0;
    int? invokedRevision;

    Widget host() {
      final callback = callbackRevision;
      final post = ThreadPost(
        pid: pid,
        author: 'author',
        authorId: '1',
        message: html,
        number: 1,
        isFirst: true,
        dateline: 'date',
      );
      return UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          theme: theme,
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ThreadPostHtmlFirstBody(
                post: post,
                threadId: tid,
                imageReferer: '',
                plan: const ThreadPostBodyRenderPlanner().plan(html),
                onOpenPostLink: (_) => invokedRevision = callback,
                onOpenPostImage: null,
                theme: const ForumHtmlRenderThemeFactory().fromMaterialTheme(
                  theme: theme,
                  surface: theme.colorScheme.surface,
                ),
                renderPreparer: activePreparer,
              ),
            ),
          ),
        ),
      );
    }

    Future<void> rebuild() async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await rebuild();
    final renderer = tester.widget<ForumHtmlWidgetPostRenderer>(
      find.byType(ForumHtmlWidgetPostRenderer),
    );
    final document = renderer.preparedDocument;
    expect(preparer.calls, 1);
    for (var i = 0; i < 20; i++) {
      callbackRevision++;
      await rebuild();
    }
    final updated = tester.widget<ForumHtmlWidgetPostRenderer>(
      find.byType(ForumHtmlWidgetPostRenderer),
    );
    expect(updated.preparedDocument, same(document));
    expect(preparer.calls, 1);
    await updated.callbacks.onTapUrl!('https://example.test');
    expect(invokedRevision, callbackRevision);

    html = '<p>edited</p>';
    await rebuild();
    expect(preparer.calls, 2);
    theme = ThemeData.dark();
    await rebuild();
    expect(preparer.calls, 3);
    pid = 'p2';
    await rebuild();
    expect(preparer.calls, 4);
    tid = '101';
    await rebuild();
    expect(preparer.calls, 5);
    repository.preferences = repository.preferences.copyWith(
      preserveAuthorFontSize: false,
    );
    container.invalidate(forumHtmlReaderPreferencesControllerProvider);
    await tester.pumpAndSettle();
    expect(preparer.calls, 6);
    activePreparer = _CountingPreparer();
    await rebuild();
    expect(activePreparer.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await rebuild();
    expect(
      activePreparer.calls,
      2,
      reason: 'Recycled rows release their prepared document.',
    );
  });
}

class _CountingPreparer implements ForumHtmlRenderPreparer {
  int calls = 0;
  @override
  ForumHtmlPreparedRenderDocument prepare({
    required String html,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  }) {
    calls++;
    return const DefaultForumHtmlRenderPreparer().prepare(
      html: html,
      preferences: preferences,
      theme: theme,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
    );
  }
}

class _PreferencesRepository implements ForumHtmlReaderPreferencesRepository {
  ForumHtmlReaderPreferences preferences =
      ForumHtmlReaderPreferences.defaults();
  @override
  Future<ForumHtmlReaderPreferences> load() async => preferences;
  @override
  Future<void> save(ForumHtmlReaderPreferences value) async =>
      preferences = value;
}
