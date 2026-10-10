import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/services/thread_post_actions.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets(
    'native post links preserve URLs and author layout on narrow screens',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(300, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = _container();
      addTearDown(container.dispose);
      const plain =
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&page=2#pid456';
      const existing = 'https://example.test/existing?q=1#anchor';
      final post = _post(
        '<p><span style="font-size:22px;color:#005522">'
        '${const HtmlEscape().convert(plain)}</span>。</p>'
        '<p><a href="$existing">Existing link</a></p>',
      );
      final events = <String>[];
      await tester.pumpWidget(
        _host(container, _content(post, events.add), textScale: 1.6),
      );
      await tester.pumpAndSettle();

      await _tapText(tester, plain);
      expect(events, [plain]);
      await _tapText(tester, 'Existing link');
      expect(events, [plain, existing]);
      final document = _document(tester);
      final fragment = html_parser.parseFragment(document.preparedHtml);
      expect(fragment.text, contains('$plain。'));
      expect(fragment.querySelectorAll('a'), hasLength(2));
      expect(fragment.querySelectorAll('a a'), isEmpty);
      expect(document.sequence.entries, isEmpty);
      final rendered = _textSpans(
        tester,
      ).where((entry) => entry.$1.contains('https://bbs.yamibo.com'));
      expect(rendered, isNotEmpty);
      expect(rendered.first.$2.fontSize, closeTo(22 * 1.6, 0.001));
      expect(rendered.first.$2.color, const Color(0xFF005522));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native callback updates retain prepared body and open folds', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    const rootUrl = 'https://example.test/root';
    const nestedUrl = 'https://example.test/nested';
    final post = _post(
      '<p>$rootUrl</p>'
      '<div id="fold" class="showcollapse_box">'
      '<div class="showcollapse_title">Fold</div>'
      '<div class="showcollapse_content"><p>$nestedUrl</p></div></div>',
    );
    var revision = 1;
    final events = <(int, String)>[];
    Widget build() {
      final current = revision;
      return _host(
        container,
        _content(post, (url) => events.add((current, url))),
      );
    }

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('forum-html-collapse-toggle-p1-fold')),
    );
    await tester.pumpAndSettle();
    final document = _document(tester);
    final body = tester.element(
      find.byKey(const Key('forum-html-renderer-p1')),
    );
    final nested = tester.element(
      find.byKey(const Key('forum-html-renderer-p1-fold-content')),
    );

    revision = 2;
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(_document(tester), same(document));
    expect(
      tester.element(find.byKey(const Key('forum-html-renderer-p1'))),
      same(body),
    );
    expect(
      tester.element(
        find.byKey(const Key('forum-html-renderer-p1-fold-content')),
      ),
      same(nested),
    );
    await _tapText(tester, rootUrl);
    await _tapText(tester, nestedUrl);
    expect(events, [(2, rootUrl), (2, nestedUrl)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared comic-style post cards keep plain URLs unlinked', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    const plain = 'https://example.test/plain';
    const existing = 'https://example.test/linked';
    final events = <String>[];
    await tester.pumpWidget(
      _host(
        container,
        Builder(
          builder: (context) => SingleChildScrollView(
            child: ThreadPostCard(
              post: _post('<p>$plain</p><p><a href="$existing">Linked</a></p>'),
              imageReferer: null,
              palette: ThreadDetailNativePalette.resolve(Theme.of(context)),
              onOpenPostLink: events.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapText(tester, plain);
    expect(events, isEmpty);
    await _tapText(tester, 'Linked');
    expect(events, [existing]);
    final fragment = html_parser.parseFragment(_document(tester).preparedHtml);
    expect(fragment.querySelectorAll('a'), hasLength(1));
    expect(fragment.querySelector('a')!.attributes['href'], existing);
    expect(fragment.text, contains(plain));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'existing native copy action passes link preparation into selection',
    (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      final observer = _Observer();
      const url = 'https://bbs.yamibo.com/thread-123-2-1.html';
      final post = _post('<p>$url</p>');
      await tester.pumpWidget(
        _host(
          container,
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ThreadPostActions(
                context: context,
                ref: ref,
                target: const ThreadPostActionContext(
                  tid: '100',
                  fid: '33',
                  subject: 'fixture',
                  page: 1,
                  capabilities: null,
                ),
                isCurrent: () => context.mounted,
                imageReferer: null,
                selectionRenderPreparer: const DefaultForumHtmlRenderPreparer(
                  enablePlainTextLinks: true,
                ),
              ).show(sourcePost: post, displayPost: post),
              child: const Text('Open actions'),
            ),
          ),
          observers: [observer],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thread-post-select-copy-action')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('thread-post-html-selection-copy-page')),
        findsOneWidget,
      );
      expect(
        html_parser
            .parseFragment(_document(tester).preparedHtml)
            .querySelector('a')!
            .attributes['href'],
        url,
      );
      final source = tester.element(find.byType(SelectionArea));
      observer.pushed.clear();
      await _tapText(tester, url);
      await tester.idle();
      expect(observer.pushed, hasLength(1));
      final route = observer.pushed.single as MaterialPageRoute;
      final destination = route.builder(source) as ThreadDetailPage;
      expect(destination.tid, '123');
      expect(destination.initialPage, 2);
      // Inspect the route before mounting its forum-backed loading page.
      Navigator.of(source).removeRoute(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

ProviderContainer _container() => ProviderContainer(
  overrides: [
    forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
      _PreferencesRepository(),
    ),
  ],
);

Widget _host(
  ProviderContainer container,
  Widget body, {
  double textScale = 1,
  List<NavigatorObserver> observers = const [],
}) => UncontrolledProviderScope(
  container: container,
  child: LocalizedTestApp(
    navigatorObservers: observers,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: body),
  ),
);

ThreadPost _post(String html) => ThreadPost(
  pid: 'p1',
  author: 'Author',
  authorId: '',
  message: html,
  number: 1,
  isFirst: false,
  dateline: 'date',
);

ThreadDetailContent _content(
  ThreadPost post,
  ValueChanged<String> onOpenLink,
) => ThreadDetailContent(
  state: ThreadDetailPageState.initial(
    tid: '100',
    subject: 'fixture',
  ).copyWith(posts: [post]),
  imageReferer: '',
  onLoadPreviousPage: () {},
  onLoadNextPage: () {},
  onLoadPageNumber: (_) {},
  onOpenAuthorProfile: (_) {},
  onOpenCommentAuthorProfile: (_) {},
  onCopyActionUrl: (_, _) {},
  onOpenPostLink: onOpenLink,
  onOpenPostActions: (_) {},
  onTogglePollOption: (_, _) {},
  onSubmitPollVote: (_) {},
);

ForumHtmlPreparedRenderDocument _document(WidgetTester tester) => tester
    .widget<ForumHtmlWidgetPostRenderer>(
      find.byType(ForumHtmlWidgetPostRenderer),
    )
    .preparedDocument!;

Future<void> _tapText(WidgetTester tester, String text) async {
  final richText = find
      .byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains(text),
      )
      .first;
  await tester.ensureVisible(richText);
  final paragraph = tester.renderObject<RenderParagraph>(richText);
  final offset = paragraph.text.toPlainText().indexOf(text);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      )
      .first;
  await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
}

Iterable<(String, TextStyle)> _textSpans(WidgetTester tester) sync* {
  Iterable<(String, TextStyle)> visit(InlineSpan span, TextStyle parent) sync* {
    final style = parent.merge(span.style);
    if (span is TextSpan) {
      if (span.text != null) yield (span.text!, style);
      for (final child in span.children ?? const <InlineSpan>[]) {
        yield* visit(child, style);
      }
    }
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    yield* visit(richText.text, const TextStyle());
  }
}

class _PreferencesRepository implements ForumHtmlReaderPreferencesRepository {
  @override
  Future<ForumHtmlReaderPreferences> load() async =>
      ForumHtmlReaderPreferences.defaults();

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {}
}

class _Observer extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}
