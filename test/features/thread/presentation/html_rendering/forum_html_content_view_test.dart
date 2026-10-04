import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

void main() {
  testWidgets(
    'relative links follow the current document across compact layout changes',
    (tester) async {
      final links = <String>[];
      final preparer = _CountingRenderPreparer();
      final repository = _FixedPreferencesRepository(
        ForumHtmlReaderPreferences.defaults(),
      );
      Future<void> show(
        Uri base, {
        ForumHtmlContentLayout contentLayout = ForumHtmlContentLayout.document,
      }) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
                repository,
              ),
            ],
            child: LocalizedTestApp(
              home: Scaffold(
                body: ForumHtmlContentView(
                  html: '<a href="#comment_5">link</a>',
                  sourceId: 'current-document',
                  linkBaseUri: base,
                  contentLayout: contentLayout,
                  renderPreparer: preparer,
                  onOpenLink: links.add,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final renderer = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
        expect(renderer.baseUrl, base);
        expect(renderer.rebuildTriggers, contains(contentLayout));
        await tester.tap(find.text('link', findRichText: true));
        await tester.pumpAndSettle();
      }

      final first = Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=space&uid=101&do=blog&id=11',
      );
      final second = first.replace(
        queryParameters: {...first.queryParameters, 'page': '3'},
      );
      await show(first);
      await show(second, contentLayout: ForumHtmlContentLayout.compact);
      expect(links, [
        first.replace(fragment: 'comment_5').toString(),
        second.replace(fragment: 'comment_5').toString(),
      ]);
      expect(preparer.callCount, 1);
    },
  );

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

  testWidgets(
    'layout changes reuse the prepared document for the same source',
    (tester) async {
      final preparer = _CountingRenderPreparer();
      final repository = _FixedPreferencesRepository(
        ForumHtmlReaderPreferences.defaults(),
      );
      final theme = ThemeData.light(useMaterial3: true);
      await tester.pumpWidget(
        _host(theme: theme, repository: repository, preparer: preparer),
      );
      await tester.pumpAndSettle();
      expect(preparer.callCount, 1);
      await tester.pumpWidget(
        _host(
          theme: theme,
          repository: repository,
          preparer: preparer,
          contentLayout: ForumHtmlContentLayout.compact,
        ),
      );
      await tester.pumpAndSettle();
      expect(preparer.callCount, 1);
      expect(
        tester.widget<HtmlWidget>(find.byType(HtmlWidget)).rebuildTriggers,
        contains(ForumHtmlContentLayout.compact),
      );
    },
  );
}

Widget _host({
  required ThemeData theme,
  required ForumHtmlReaderPreferencesRepository repository,
  required ForumHtmlRenderPreparer preparer,
  ForumHtmlContentLayout contentLayout = ForumHtmlContentLayout.document,
}) {
  return ProviderScope(
    overrides: [
      forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
        repository,
      ),
    ],
    child: LocalizedTestApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: ForumHtmlContentView(
          html: '<font id="body" color="black">共享正文</font>',
          sourceId: 'shared-content',
          renderPreparer: preparer,
          contentLayout: contentLayout,
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
