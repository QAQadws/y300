import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../../../test_support/localized_test_app.dart';

class _Clipboard implements ClipboardTextWriter {
  @override
  Future<void> writeText(String text) async {}
}

final class _Fixture {
  _Fixture({String html = '<p>target text</p>'}) {
    prepared = const DefaultForumHtmlRenderPreparer().prepare(
      html: html,
      preferences: preferences,
      theme: theme,
      sourceId: 'target',
      threadId: 'thread',
      imageCacheOwnerId: 'thread',
    );
    document = const ForumBodyParser().parse(
      html: prepared.preparedHtml,
      sourceId: 'target',
      conversionIdentity: 'prepared-forum-body',
    );
    addTearDown(() {
      preloads.dispose();
      presentation.dispose();
      cache.close();
    });
  }
  final cache = ForumNativeBodyCache();
  final preloads = ForumNativeBodyFlowPreloads();
  final presentation = ForumHtmlBodyPresentation();
  final preferences = ForumHtmlReaderPreferences.defaults();
  final theme = const ForumHtmlRenderThemeFactory().fromMaterialTheme(
    theme: ThemeData.light(),
    surface: Colors.white,
  );
  final double width = 200;
  final TextScaler scaler = TextScaler.noScaling;
  late final ForumHtmlPreparedRenderDocument prepared;
  late final ForumBodyDocument document;
  final ticket = Object();
  final style = const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 10,
    height: 1,
    locale: Locale('zh'),
  );

  ForumNativeBodyFlowInput input({
    double? width,
    String font = 'ahem',
    TextScaler? scaler,
    Map<String, bool>? expansion,
  }) => ForumNativeBodyFlowInput(
    document: document,
    prepared: prepared,
    width: width ?? this.width,
    textStyle: style,
    fontRevision: font,
    textScaler: scaler ?? this.scaler,
    direction: TextDirection.ltr,
    paragraphAfter: preferences.typography.paragraphSpacing,
    theme: theme,
    cache: cache.paragraphs,
    host: null,
    expansion: expansion ?? presentation.collapseExpansion,
    presentation: presentation,
    preparationIdentity: 'request',
    resourceIdentity: 'resource',
  );

  Future<bool> prepare({bool bottom = false, double extent = 400}) {
    preloads.begin(ticket);
    return preloads.prepare(
      ticket: ticket,
      input: input(),
      bottom: bottom,
      extent: extent,
    );
  }

  Widget widget() => LocalizedTestApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: ForumNativeBodyFlowPreloadScope(
          controller: preloads,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 200,
              child: SingleChildScrollView(
                child: ForumNativeBodyFlow(
                  prepared: prepared,
                  preferences: preferences,
                  theme: theme,
                  textStyle: style,
                  fontRevision: 'ahem',
                  imageHost: null,
                  expansion: presentation.collapseExpansion,
                  bodyPresentation: presentation,
                  cache: cache,
                  preparationIdentity: 'request',
                  resourceIdentity: 'resource',
                  callbacks: const ForumHtmlRenderCallbacks(),
                  clipboardTextWriter: _Clipboard(),
                  selectionEnabled: false,
                  errorBuilder: (_) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<T> _complete<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  Object? failure;
  T? value;
  future.then(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object e) {
      failure = e;
      done = true;
    },
  );
  for (var i = 0; i < 200 && !done; i++) {
    await tester.pump();
  }
  expect(done, isTrue);
  if (failure != null) throw failure!;
  return value as T;
}

void main() {
  for (final table in [false, true]) {
    testWidgets(
      'unmounted ${table ? 'nested table' : 'body'} transfers prepared source on its first content frame',
      (tester) async {
        final fixture = _Fixture(
          html: table
              ? '<table width="180"><tr><td>left</td><td><table><tr><td>nested</td></tr></table></td></tr></table>'
              : '<p>target text</p><p>second paragraph</p>',
        );
        expect(await _complete(tester, fixture.prepare()), isTrue);
        expect(find.byType(ForumBodyFlowBox), findsNothing);
        final source = fixture.preloads.peek('request')!.source;
        final builds = fixture.cache.paragraphs.layoutBuildCount;
        await tester.pumpWidget(fixture.widget());
        final box = tester.widget<ForumBodyFlowBox>(
          find.byType(ForumBodyFlowBox),
        );
        expect(box.session, same(source.session));
        expect(find.byType(ForumBodyParagraphSurface), findsWidgets);
        expect(fixture.cache.paragraphs.layoutBuildCount, builds);
        fixture.preloads.cancel(fixture.ticket);
        expect(source.isClosed, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(source.isClosed, isTrue);
        expect(fixture.cache.paragraphs.activeLeases, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('top demand suspends at its prefix and resumes after handoff', (
    tester,
  ) async {
    final fixture = _Fixture(
      html: List.generate(
        200,
        (i) => '<p>paragraph $i ${'text ' * 10}</p>',
      ).join(),
    );
    expect(await _complete(tester, fixture.prepare(extent: 200)), isTrue);
    final source = fixture.preloads.peek('request')!.source;
    final prefix = source.prefix!;
    expect(prefix.isComplete, isFalse);
    expect(source.isSuspended, isTrue);
    await tester.pumpWidget(fixture.widget());
    expect(
      tester.widget<ForumBodyFlowBox>(find.byType(ForumBodyFlowBox)).session,
      same(source.session),
    );
    await tester.pumpAndSettle();
    expect(source.prefix!.isComplete, isTrue);
    expect(source.prefix![0], same(prefix[0]));
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.preloads.cancel();
    expect(fixture.cache.paragraphs.activeLeases, 0);
  });

  testWidgets(
    'bottom demand prepares the last window, not just the first page',
    (tester) async {
      final fixture = _Fixture(
        html: List.generate(
          70,
          (i) => '<p>paragraph $i ${'text ' * 5}</p>',
        ).join(),
      );
      expect(
        await _complete(tester, fixture.prepare(bottom: true, extent: 200)),
        isTrue,
      );
      final source = fixture.preloads.peek('request')!.source;
      expect(source.prefix!.isComplete, isTrue);
      final seed = fixture.preloads.take(fixture.input())!;
      expect(seed.slices.last.index, source.prefix!.length - 1);
      for (final slice in seed.slices) {
        slice.close();
      }
      source.close();
      fixture.preloads.cancel();
      expect(fixture.cache.paragraphs.activeLeases, 0);
    },
  );

  testWidgets('width font scaling and folds reject stale deliveries', (
    tester,
  ) async {
    final fixture = _Fixture();
    expect(await _complete(tester, fixture.prepare()), isTrue);
    for (final input in [
      fixture.input(width: 199),
      fixture.input(font: 'new-font'),
      fixture.input(scaler: const TextScaler.linear(1.1)),
      fixture.input(expansion: {'fold': true}),
    ]) {
      expect(fixture.preloads.take(input), isNull);
    }
    final source = fixture.preloads.peek('request')!.source;
    fixture.preloads.cancel();
    expect(source.isClosed, isTrue);
    expect(fixture.cache.paragraphs.activeLeases, 0);
  });

  testWidgets('cancelled and replaced requests retire only their own sources', (
    tester,
  ) async {
    final fixture = _Fixture();
    final pending = fixture.prepare();
    final old = fixture.preloads.peek('request')!.source;
    final next = Object();
    fixture.preloads.begin(next);
    expect(old.isClosed, isTrue);
    final result = fixture.preloads.prepare(
      ticket: next,
      input: fixture.input(),
      bottom: false,
      extent: 200,
    );
    fixture.preloads.cancel(fixture.ticket);
    expect(fixture.preloads.isCurrent(next), isTrue);
    expect(await _complete(tester, pending), isFalse);
    expect(await _complete(tester, result), isTrue);
    final current = fixture.preloads.peek('request')!.source;
    fixture.preloads.cancel(next);
    expect(current.isClosed, isTrue);
    expect(fixture.cache.paragraphs.activeLeases, 0);
  });

  testWidgets(
    'borrowed source survives demand cancellation and keeps mounted delivery',
    (tester) async {
      final fixture = _Fixture();
      await tester.pumpWidget(fixture.widget());
      await tester.pumpAndSettle();
      final source = fixture.preloads.peek('request')!.source;
      final fragments = tester
          .widget<ForumBodyFlowBox>(find.byType(ForumBodyFlowBox))
          .session
          .activeIssuedFragments;
      expect(await _complete(tester, fixture.prepare()), isTrue);
      await tester.pump();
      fixture.preloads.cancel();
      expect(source.isClosed, isFalse);
      expect(source.session!.activeIssuedFragments, fragments);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.cache.paragraphs.activeLeases, 0);
    },
  );
}
