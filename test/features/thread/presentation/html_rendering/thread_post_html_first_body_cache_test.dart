import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('default preparation survives typography changes and relayouts', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          _PreferencesRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final codec = _CountingFragmentCodec();
    final preparer = DefaultForumHtmlRenderPreparer(fragmentCodec: codec);
    final theme = ThemeData.light();
    final post = ThreadPost(
      pid: 'typography',
      author: 'author',
      authorId: '1',
      message: '<font size="5">First line</font><p>Second line</p>',
      number: 1,
      isFirst: true,
      dateline: 'date',
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          theme: theme,
          home: Scaffold(
            body: ThreadPostHtmlFirstBody(
              post: post,
              threadId: '123',
              imageReferer: '',
              onOpenPostLink: (_) {},
              onOpenPostImage: null,
              theme: const ForumHtmlRenderThemeFactory().fromMaterialTheme(
                theme: theme,
                surface: theme.colorScheme.surface,
              ),
              renderPreparer: preparer,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    ForumHtmlWidgetPostRenderer renderer() =>
        tester.widget(find.byType(ForumHtmlWidgetPostRenderer));
    final original = renderer().preparedDocument!;
    final firstHeight = tester
        .getSize(find.text('First line', findRichText: true))
        .height;
    final controller = container.read(
      forumHtmlReaderPreferencesControllerProvider.notifier,
    );
    await controller.setTypography(
      renderer().preferences!.typography.copyWith(
        fontScale: 1.8,
        lineHeightScale: 2.0,
      ),
    );
    await tester.pumpAndSettle();
    expect(renderer().preparedDocument, same(original));
    expect(codec.parseCount, 1);
    expect(
      tester.getSize(find.text('First line', findRichText: true)).height,
      greaterThan(firstHeight),
    );
    await controller.setConversionMode(TextConversionMode.toSimplified);
    await tester.pumpAndSettle();
    expect(renderer().preparedDocument, same(original));
    expect(codec.parseCount, 1);
    await controller.setPreserveAuthorFontSize(false);
    await tester.pumpAndSettle();
    expect(renderer().preparedDocument, isNot(same(original)));
    expect(codec.parseCount, 2);
    expect(
      renderer().preparedDocument!.preparedHtml,
      isNot(contains('font-size')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('link capability changes invalidate only the prepared document', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          _PreferencesRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    const url = 'https://bbs.yamibo.com/thread-123-2-1.html';
    final post = ThreadPost(
      pid: 'plain-link',
      author: 'author',
      authorId: '1',
      message: '<p>$url</p>',
      number: 1,
      isFirst: true,
      dateline: 'date',
    );
    var enabled = false;
    var callbackRevision = 0;
    int? invokedRevision;
    Widget host() {
      final revision = callbackRevision;
      final theme = ThemeData.light();
      return UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          theme: theme,
          home: Scaffold(
            body: ThreadPostHtmlFirstBody(
              post: post,
              threadId: '123',
              imageReferer: '',
              onOpenPostLink: (_) => invokedRevision = revision,
              onOpenPostImage: null,
              theme: const ForumHtmlRenderThemeFactory().fromMaterialTheme(
                theme: theme,
                surface: theme.colorScheme.surface,
              ),
              renderPreparer: enabled
                  ? const DefaultForumHtmlRenderPreparer(
                      enablePlainTextLinks: true,
                    )
                  : const DefaultForumHtmlRenderPreparer(),
            ),
          ),
        ),
      );
    }

    ForumHtmlWidgetPostRenderer renderer() =>
        tester.widget(find.byType(ForumHtmlWidgetPostRenderer));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final original = renderer().preparedDocument!;
    final element = tester.element(find.byType(ThreadPostHtmlFirstBody));
    expect(original.preparedHtml, isNot(contains('href=')));

    enabled = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final linked = renderer().preparedDocument!;
    expect(linked, isNot(same(original)));
    expect(linked.preparedHtml, contains('href="$url"'));
    expect(tester.element(find.byType(ThreadPostHtmlFirstBody)), same(element));

    callbackRevision++;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(renderer().preparedDocument, same(linked));
    await renderer().callbacks.onTapUrl!(url);
    expect(invokedRevision, callbackRevision);

    enabled = false;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(renderer().preparedDocument!.preparedHtml, original.preparedHtml);
    expect(tester.takeException(), isNull);
  });

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
    final controller = container.read(
      forumHtmlReaderPreferencesControllerProvider.notifier,
    );
    await controller.setFontScale(1.8);
    await tester.pumpAndSettle();
    expect(preparer.calls, 7, reason: 'Injected preparers may use typography.');
    await controller.setConversionMode(TextConversionMode.toSimplified);
    await tester.pumpAndSettle();
    expect(preparer.calls, 8, reason: 'Injected preparers may use conversion.');
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

final class _CountingFragmentCodec implements ForumHtmlFragmentCodec {
  final _delegate = const HtmlPackageForumHtmlFragmentCodec();
  int parseCount = 0;

  @override
  html_dom.DocumentFragment parse(String html) {
    parseCount++;
    return _delegate.parse(html);
  }

  @override
  String serialize(html_dom.DocumentFragment fragment) =>
      _delegate.serialize(fragment);
}
