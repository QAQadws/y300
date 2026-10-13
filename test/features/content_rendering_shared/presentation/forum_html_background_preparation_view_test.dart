import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets(
    'content view replaces the previous body with a pending placeholder',
    (tester) async {
      final worker = _Worker();
      final executor = _executor(worker);
      final scope = _Scope();
      Widget scene(String html) => scope.host(
        ForumHtmlContentView(
          html: html,
          sourceId: 'body',
          theme: _lightTheme,
          preparationExecutor: executor,
        ),
      );
      await tester.pumpWidget(scene('<p>First body</p>'));
      await _frames(tester);
      expect(worker.jobs, hasLength(1));
      expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
      expect(find.byType(ForumHtmlRenderer), findsNothing);
      worker.complete(0);
      await _frames(tester);
      expect(find.text('First body', findRichText: true), findsOneWidget);

      await tester.pumpWidget(scene('<p>Next body</p>'));
      await _frames(tester);
      expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
      expect(find.text('First body', findRichText: true), findsNothing);
      expect(find.byType(ForumHtmlRenderer), findsNothing);
      worker.complete(1);
      await _frames(tester);
      expect(find.text('Next body', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('content view rejects retired HTML theme and owner results', (
    tester,
  ) async {
    final worker = _Worker();
    final executor = _executor(worker);
    final scope = _Scope();
    Widget scene(String html, ForumHtmlThemeContext theme, String owner) =>
        scope.host(
          ForumHtmlContentView(
            html: html,
            sourceId: 'body',
            imageCacheOwnerId: owner,
            theme: theme,
            preparationExecutor: executor,
          ),
        );
    await tester.pumpWidget(
      scene('<p>Retired body</p>', _lightTheme, 'owner-A'),
    );
    await tester.pumpWidget(
      scene('<p>Current body</p>', _lightTheme, 'owner-A'),
    );
    await tester.pumpWidget(
      scene('<p>Current body</p>', _darkTheme, 'owner-A'),
    );
    await tester.pumpWidget(
      scene('<p>Current body</p>', _darkTheme, 'owner-B'),
    );
    expect(worker.jobs, hasLength(4));
    for (var index = 0; index < 3; index++) {
      worker.complete(index);
      await _frames(tester);
      expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
      expect(find.byType(ForumHtmlRenderer), findsNothing);
    }
    expect(worker.jobs.last.input.imageCacheOwnerId, 'owner-B');
    expect(worker.jobs.last.input.theme.signature, _darkTheme.signature);
    worker.complete(3);
    await _frames(tester);
    expect(find.text('Current body', findRichText: true), findsOneWidget);
    expect(find.text('Retired body', findRichText: true), findsNothing);
    expect(
      tester
          .widget<ForumHtmlRenderer>(find.byType(ForumHtmlRenderer))
          .preparedDocument
          .themeSignature,
      _darkTheme.signature,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty input executor rebinding and disposal retire content leases',
    (tester) async {
      final first = _Worker();
      final second = _Worker();
      final firstExecutor = _executor(first);
      final secondExecutor = _executor(second);
      final scope = _Scope();
      Widget scene(String html, ForumHtmlPreparationExecutor executor) =>
          scope.host(
            ForumHtmlContentView(
              html: html,
              sourceId: 'body',
              theme: _lightTheme,
              preparationExecutor: executor,
            ),
          );
      await tester.pumpWidget(
        scene('<p>Retired empty body</p>', firstExecutor),
      );
      await tester.pumpWidget(scene('', firstExecutor));
      expect(find.byType(ForumHtmlPreparationPlaceholder), findsNothing);
      first.complete(0);
      await _frames(tester);
      expect(find.byType(ForumHtmlRenderer), findsNothing);

      await tester.pumpWidget(scene('<p>Rebound body</p>', firstExecutor));
      await tester.pumpWidget(scene('<p>Rebound body</p>', secondExecutor));
      first.complete(1);
      await _frames(tester);
      expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
      second.complete(0);
      await _frames(tester);
      expect(find.text('Rebound body', findRichText: true), findsOneWidget);

      await tester.pumpWidget(scene('<p>Disposed body</p>', secondExecutor));
      await tester.pumpWidget(const SizedBox.shrink());
      second.complete(1);
      await _frames(tester);
      expect(find.text('Disposed body', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom content preparer stays synchronous with threshold zero', (
    tester,
  ) async {
    final worker = _Worker();
    final executor = _executor(worker);
    final preparer = _CustomPreparer();
    await tester.pumpWidget(
      _Scope().host(
        ForumHtmlContentView(
          html: '<p>Custom body</p>',
          sourceId: 'custom',
          theme: _lightTheme,
          renderPreparer: preparer,
          preparationExecutor: executor,
        ),
      ),
    );
    await _frames(tester);
    expect(worker.jobs, isEmpty);
    expect(preparer.calls, 1);
    expect(find.byType(ForumHtmlPreparationPlaceholder), findsNothing);
    expect(find.text('Custom body', findRichText: true), findsOneWidget);
  });

  testWidgets(
    'fallback renderer reports readiness only after real prepared content',
    (tester) async {
      final worker = _Worker();
      final executor = _executor(worker);
      var ready = 0;
      Widget scene(String html) => _Scope.shell(
        ForumHtmlWidgetPostRenderer(
          html: html,
          theme: _lightTheme,
          sourceId: 'fallback',
          preparationExecutor: executor,
          onBodyBuilt: () => ready++,
          buildAsync: false,
        ),
      );
      await tester.pumpWidget(scene('<p>First fallback</p>'));
      await _frames(tester);
      expect(ready, 0);
      expect(find.byType(ForumHtmlRenderer), findsNothing);
      worker.complete(0);
      await _frames(tester);
      expect(ready, greaterThan(0));
      final firstReady = ready;
      await tester.pumpWidget(scene('<p>Next fallback</p>'));
      await _frames(tester);
      expect(ready, firstReady);
      expect(find.text('First fallback', findRichText: true), findsNothing);
      expect(find.byType(ForumHtmlRenderer), findsNothing);
      worker.complete(1);
      await _frames(tester);
      expect(ready, greaterThan(firstReady));
      expect(find.text('Next fallback', findRichText: true), findsOneWidget);
    },
  );

  testWidgets('supplied document takes over an already pending fallback', (
    tester,
  ) async {
    final worker = _Worker();
    final executor = _executor(worker);
    final supplied = const DefaultForumHtmlRenderPreparer().prepare(
      html: '<p>Supplied body</p>',
      preferences: ForumHtmlReaderPreferences.defaults(),
      theme: _lightTheme,
      sourceId: 'fallback',
      threadId: null,
      imageCacheOwnerId: null,
    );
    Widget scene({ForumHtmlPreparedRenderDocument? document}) => _Scope.shell(
      ForumHtmlWidgetPostRenderer(
        html: '<p>Retired fallback</p>',
        theme: _lightTheme,
        sourceId: 'fallback',
        preparedDocument: document,
        preparationExecutor: executor,
        buildAsync: false,
      ),
    );
    await tester.pumpWidget(scene());
    expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
    await tester.pumpWidget(scene(document: supplied));
    await _frames(tester);
    expect(find.text('Supplied body', findRichText: true), findsOneWidget);
    worker.complete(0);
    await _frames(tester);
    expect(find.text('Supplied body', findRichText: true), findsOneWidget);
    expect(find.text('Retired fallback', findRichText: true), findsNothing);
    expect(
      tester
          .widget<ForumHtmlRenderer>(find.byType(ForumHtmlRenderer))
          .preparedDocument,
      same(supplied),
    );
    await tester.pumpWidget(scene());
    expect(worker.jobs, hasLength(2));
    worker.complete(1);
    await _frames(tester);
    expect(find.text('Retired fallback', findRichText: true), findsOneWidget);
  });

  testWidgets(
    'fallback identity and executor changes retire earlier pending leases',
    (tester) async {
      final first = _Worker();
      final second = _Worker();
      final firstExecutor = _executor(first);
      final secondExecutor = _executor(second);
      Widget scene(
        String html,
        ForumHtmlThemeContext theme,
        String owner,
        ForumHtmlPreparationExecutor executor,
      ) => _Scope.shell(
        ForumHtmlWidgetPostRenderer(
          html: html,
          theme: theme,
          sourceId: 'fallback',
          threadId: '100',
          imageCacheOwnerId: owner,
          preparationExecutor: executor,
          buildAsync: false,
        ),
      );
      await tester.pumpWidget(
        scene('<p>Retired body</p>', _lightTheme, 'owner-A', firstExecutor),
      );
      await tester.pumpWidget(
        scene('<p>Rebound body</p>', _darkTheme, 'owner-B', firstExecutor),
      );
      await tester.pumpWidget(
        scene('<p>Rebound body</p>', _darkTheme, 'owner-B', secondExecutor),
      );
      first.complete(1);
      first.complete(0);
      await _frames(tester);
      expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
      expect(find.byType(ForumHtmlRenderer), findsNothing);
      expect(second.jobs.single.input.imageCacheOwnerId, 'owner-B');
      expect(second.jobs.single.input.theme.signature, _darkTheme.signature);
      second.complete(0);
      await _frames(tester);
      expect(find.text('Rebound body', findRichText: true), findsOneWidget);
      expect(find.text('Retired body', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending fallback remains a sliver and disposal ignores completion',
    (tester) async {
      final worker = _Worker();
      final executor = _executor(worker);
      var ready = 0;
      await tester.pumpWidget(
        _Scope.shell(
          CustomScrollView(
            slivers: [
              ForumHtmlWidgetPostRenderer(
                html: '<p>Sliver fallback</p>',
                theme: _lightTheme,
                preparationExecutor: executor,
                renderMode: RenderMode.sliverList,
                onBodyBuilt: () => ready++,
                buildAsync: false,
              ),
            ],
          ),
        ),
      );
      await _frames(tester);
      expect(find.byType(ForumHtmlPreparationPlaceholder), findsOneWidget);
      expect(ready, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      worker.complete(0);
      await _frames(tester);
      expect(ready, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _frames(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    await tester.pump();
  }
}

ForumHtmlPreparationExecutor _executor(_Worker worker) {
  final executor = ForumHtmlPreparationExecutor(
    codeUnitThreshold: 0,
    maxConcurrent: 4,
    worker: worker.call,
  );
  addTearDown(executor.dispose);
  return executor;
}

final class _Worker {
  final jobs =
      <
        ({
          ForumHtmlBackgroundPreparationInput input,
          Completer<ForumHtmlPreparedRenderDocument> result,
        })
      >[];

  Future<ForumHtmlPreparedRenderDocument> call(
    ForumHtmlBackgroundPreparationInput input,
  ) {
    final result = Completer<ForumHtmlPreparedRenderDocument>();
    jobs.add((input: input, result: result));
    return result.future;
  }

  void complete(int index) =>
      jobs[index].result.complete(jobs[index].input.prepare());
}

final class _Scope {
  _Scope() {
    addTearDown(container.dispose);
  }

  final container = ProviderContainer(
    overrides: [
      forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
        const _Preferences(),
      ),
    ],
  );

  Widget host(Widget body) =>
      UncontrolledProviderScope(container: container, child: shell(body));

  static Widget shell(Widget body) => LocalizedTestApp(
    themeAnimationDuration: Duration.zero,
    home: Scaffold(body: body),
  );
}

final class _Preferences implements ForumHtmlReaderPreferencesRepository {
  const _Preferences();

  @override
  Future<ForumHtmlReaderPreferences> load() async =>
      ForumHtmlReaderPreferences.defaults();

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {}
}

final class _CustomPreparer implements ForumHtmlRenderPreparer {
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

final _lightTheme = const ForumHtmlRenderThemeFactory().fromMaterialTheme(
  theme: ThemeData.light(),
  surface: ThemeData.light().colorScheme.surface,
);
final _darkTheme = const ForumHtmlRenderThemeFactory().fromMaterialTheme(
  theme: ThemeData.dark(),
  surface: ThemeData.dark().colorScheme.surface,
);
