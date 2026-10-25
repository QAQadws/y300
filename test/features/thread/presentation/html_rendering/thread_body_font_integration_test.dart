import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_repository.dart';
import 'package:y300/features/fonts/domain/services/font_runtime_loader.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/thread/domain/contracts/thread_body_reading_observer.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_first_body.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_selection_copy_page.dart';
import 'package:y300/features/thread/presentation/services/thread_body_reading_coordinator.dart';

import '../../../../test_support/localized_test_app.dart';

const _first = ImportedFont(
  id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  displayName: 'First',
  storageFileName: 'first.ttf',
  byteLength: 1,
);
const _second = ImportedFont(
  id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  displayName: 'Second',
  storageFileName: 'second.ttf',
  byteLength: 1,
);
const _html =
    '<p>Default body</p>'
    '<p style="font-family: AuthorFont; font-weight:700"><i>Author emphasis</i></p>'
    '<div id="fold" class="showcollapse_box">'
    '<div class="showcollapse_title">Details</div>'
    '<div class="showcollapse_content">Expanded body</div></div>';

void main() {
  late _Preferences preferences;
  late _Fonts fonts;
  late _Runtime runtime;
  late FontLibraryService service;
  late ProviderContainer container;

  setUp(() {
    preferences = _Preferences();
    fonts = _Fonts();
    runtime = _Runtime();
    service = FontLibraryService(repository: fonts, runtimeLoader: runtime);
    container = ProviderContainer(
      overrides: [
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          preferences,
        ),
        fontLibraryServiceProvider.overrideWithValue(service),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    service.dispose();
    await fonts.dispose();
  });

  testWidgets('cold body waits for preferences and the selected runtime font', (
    tester,
  ) async {
    final loadedPreferences = Completer<ForumHtmlReaderPreferences>();
    final loadedFont = Completer<void>();
    preferences.pendingLoad = loadedPreferences.future;
    runtime.gates[_first.id] = loadedFont;
    await tester.pumpWidget(_app(container));
    await tester.pump();
    expect(find.byType(ForumHtmlWidgetPostRenderer), findsNothing);
    loadedPreferences.complete(
      preferences.value.copyWith(fontFamily: _first.id),
    );
    await _pumpUntil(tester, () => runtime.requested.contains(_first.id));
    expect(find.byType(ForumHtmlWidgetPostRenderer), findsNothing);
    loadedFont.complete();
    await _ready(tester, FontIdentity.runtimeFamily(_first.id));
    expect(preferences.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'font-neutral preparation runs while the selected font is pending',
    (tester) async {
      preferences.value = preferences.value.copyWith(fontFamily: _first.id);
      final loadedFont = Completer<void>();
      runtime.gates[_first.id] = loadedFont;
      final jobs = <ForumHtmlBackgroundPreparationInput>[];
      final prepared = Completer<ForumHtmlPreparedRenderDocument>();
      final executor = ForumHtmlPreparationExecutor(
        codeUnitThreshold: 0,
        worker: (input) {
          jobs.add(input);
          return prepared.future;
        },
      );
      addTearDown(executor.dispose);
      await tester.pumpWidget(_app(container, preparationExecutor: executor));
      expect(jobs, hasLength(1));
      await _pumpUntil(tester, () => runtime.requested.contains(_first.id));
      final document = jobs.single.prepare();
      prepared.complete(document);
      await _pumpUntil(tester, () => executor.activeCount == 0);
      expect(find.byType(ForumHtmlWidgetPostRenderer), findsNothing);
      loadedFont.complete();
      await _ready(tester, FontIdentity.runtimeFamily(_first.id));
      expect(jobs, hasLength(1));
      expect(_renderer(tester).preparedDocument, same(document));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'font loading retains readable HTML and expanded folds without scaling twice',
    (tester) async {
      preferences.value = preferences.value.copyWith(
        typography: preferences.value.typography.copyWith(fontScale: 1.6),
      );
      final scrollController = ScrollController();
      final reading = ThreadBodyReadingCoordinator(
        observer: _ReadingObserver(),
        scrollController: scrollController,
        initialTargetPid: null,
      );
      addTearDown(reading.dispose);
      addTearDown(scrollController.dispose);
      await tester.pumpWidget(_app(container, readingCoordinator: reading));
      await _ready(tester, null);
      await tester.tap(
        find.byKey(const Key('forum-html-collapse-toggle-font-post-fold')),
      );
      await tester.pumpAndSettle();
      final document = _renderer(tester).preparedDocument;
      final bodyElement = tester.element(
        find.byKey(const Key('forum-html-renderer-font-post')),
      );
      final nestedElement = tester.element(
        find.byKey(const Key('forum-html-renderer-font-post-fold-content')),
      );
      final loadedFont = Completer<void>();
      runtime.gates[_first.id] = loadedFont;
      final selection = _controller(container).setFontFamily(_first.id);
      await _pumpUntil(tester, () => runtime.requested.contains(_first.id));
      expect(find.text('Default body', findRichText: true), findsOneWidget);
      expect(_renderer(tester).textStyle!.fontFamily, _systemFamily(tester));
      expect(
        tester.element(find.byKey(const Key('forum-html-renderer-font-post'))),
        same(bodyElement),
      );
      loadedFont.complete();
      await selection;
      await _ready(tester, FontIdentity.runtimeFamily(_first.id));
      expect(_renderer(tester).preparedDocument, same(document));
      expect(
        tester.element(find.byKey(const Key('forum-html-renderer-font-post'))),
        same(bodyElement),
      );
      expect(
        tester.element(
          find.byKey(const Key('forum-html-renderer-font-post-fold-content')),
        ),
        same(nestedElement),
      );
      expect(find.text('Expanded body', findRichText: true), findsOneWidget);
      expect(_renderer(tester).textStyle!.fontSize, closeTo(20 * 1.6, 0.001));
      expect(
        _styleForText(tester, 'Default body').fontSize,
        closeTo(20 * 1.6, 0.001),
      );
      final authorStyle = _styleForText(tester, 'Author emphasis');
      expect(authorStyle.fontFamily, 'AuthorFont');
      expect(authorStyle.fontWeight, FontWeight.w700);
      expect(authorStyle.fontStyle, FontStyle.italic);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an open selection-copy page follows shared font changes and active deletion',
    (tester) async {
      preferences.value = preferences.value.copyWith(
        fontFamily: _first.id,
        typography: preferences.value.typography.copyWith(fontScale: 1.4),
      );
      await tester.pumpWidget(_app(container, selection: true));
      await _ready(tester, FontIdentity.runtimeFamily(_first.id));
      final selectionElement = tester.element(find.byType(SelectionArea));
      final bodyElement = tester.element(
        find.byKey(const Key('forum-html-renderer-font-post')),
      );
      final document = _renderer(tester).preparedDocument;
      final loadedFont = Completer<void>();
      runtime.gates[_second.id] = loadedFont;
      final selection = _controller(container).setFontFamily(_second.id);
      await _pumpUntil(tester, () => runtime.requested.contains(_second.id));
      expect(
        _renderer(tester).textStyle!.fontFamily,
        FontIdentity.runtimeFamily(_first.id),
      );
      loadedFont.complete();
      await selection;
      await _ready(tester, FontIdentity.runtimeFamily(_second.id));
      await tester.runAsync(() => service.deleteFont(_second.id));
      await _ready(tester, null);
      await tester.pumpAndSettle();
      expect(preferences.value.fontFamily, FontIdentity.system);
      expect(preferences.value.typography.fontScale, 1.4);
      expect(_renderer(tester).preparedDocument, same(document));
      expect(
        tester.element(find.byType(SelectionArea)),
        same(selectionElement),
      );
      expect(
        tester.element(find.byKey(const Key('forum-html-renderer-font-post'))),
        same(bodyElement),
      );
      expect(find.text('Default body', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

ForumHtmlReaderPreferencesController _controller(ProviderContainer container) =>
    container.read(forumHtmlReaderPreferencesControllerProvider.notifier);

ForumHtmlWidgetPostRenderer _renderer(WidgetTester tester) =>
    tester.widget(find.byType(ForumHtmlWidgetPostRenderer));

Future<void> _ready(WidgetTester tester, String? family) async {
  await _pumpUntil(tester, () {
    final rendered = find.byType(ForumHtmlWidgetPostRenderer);
    if (rendered.evaluate().length != 1) return false;
    return _renderer(tester).textStyle?.fontFamily ==
            (family ?? _systemFamily(tester)) &&
        find.text('Default body', findRichText: true).evaluate().isNotEmpty;
  });
  await tester.pumpAndSettle();
}

String? _systemFamily(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(ForumHtmlWidgetPostRenderer)))
        .textTheme
        .bodyMedium
        ?.fontFamily;

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 200; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) return;
  }
  fail('Thread body did not reach the requested font state');
}

TextStyle _styleForText(WidgetTester tester, String text) {
  TextStyle? matching(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) return null;
    final style = inherited.merge(span.style);
    if (span.text?.contains(text) == true) return style;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = matching(child, style);
      if (found != null) return found;
    }
    return null;
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final found = matching(richText.text, const TextStyle());
    if (found != null) return found;
  }
  fail('No rendered style for $text');
}

Widget _app(
  ProviderContainer container, {
  bool selection = false,
  ThreadBodyReadingCoordinator? readingCoordinator,
  ForumHtmlPreparationExecutor? preparationExecutor,
}) {
  final theme = ThemeData.light().copyWith(
    textTheme: ThemeData.light().textTheme.copyWith(
      bodyMedium: const TextStyle(fontSize: 20),
    ),
  );
  final post = ThreadPost(
    pid: 'font-post',
    author: 'author',
    authorId: '1',
    message: _html,
    number: 1,
    isFirst: true,
    dateline: 'date',
  );
  final child = selection
      ? ThreadPostHtmlSelectionCopyPage(
          post: post,
          threadId: '123',
          imageReferer: '',
          onOpenPostLink: (_) {},
          onOpenPostImage: null,
          onImageFallback: (_, _) {},
        )
      : Scaffold(
          body: SingleChildScrollView(
            child: ThreadPostHtmlFirstBody(
              post: post,
              threadId: '123',
              imageReferer: '',
              onOpenPostLink: (_) {},
              readingCoordinator: readingCoordinator,
              preparationExecutor: preparationExecutor,
              onOpenPostImage: null,
              theme: const ForumHtmlRenderThemeFactory().fromMaterialTheme(
                theme: theme,
                surface: theme.colorScheme.surface,
              ),
            ),
          ),
        );
  return UncontrolledProviderScope(
    container: container,
    child: LocalizedTestApp(theme: theme, home: child),
  );
}

final class _Preferences implements ForumHtmlReaderPreferencesRepository {
  ForumHtmlReaderPreferences value = ForumHtmlReaderPreferences.defaults();
  Future<ForumHtmlReaderPreferences>? pendingLoad;
  final saved = <ForumHtmlReaderPreferences>[];
  @override
  Future<ForumHtmlReaderPreferences> load() async =>
      value = await (pendingLoad ?? Future.value(value));
  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    value = preferences;
    saved.add(preferences);
  }
}

final class _Fonts implements FontLibraryRepository {
  final entries = <String, ImportedFont>{
    _first.id: _first,
    _second.id: _second,
  };
  final _changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<List<ImportedFont>> listFonts() async =>
      List.unmodifiable(entries.values);
  @override
  Future<Uint8List> readFont(String fontId) async {
    if (!entries.containsKey(fontId)) {
      throw const FontLibraryException(FontLibraryFailure.notFound);
    }
    return Uint8List(1);
  }

  @override
  Future<void> deleteFont(String fontId) async {
    entries.remove(fontId);
    _changes.add(null);
  }

  @override
  Future<void> dispose() => _changes.close();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected font repository call');
}

final class _Runtime implements FontRuntimeLoader {
  final gates = <String, Completer<void>>{};
  final requested = <String>[];
  @override
  Future<String> load(ImportedFont font, Uint8List bytes) async {
    requested.add(font.id);
    await gates[font.id]?.future;
    return FontIdentity.runtimeFamily(font.id);
  }
}

final class _ReadingObserver implements ThreadBodyReadingObserver {
  @override
  bool tracks(String tid, String pid) => tid == '123' && pid == 'font-post';
  @override
  void cancelPendingCompletion() {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected reading observer call');
}
