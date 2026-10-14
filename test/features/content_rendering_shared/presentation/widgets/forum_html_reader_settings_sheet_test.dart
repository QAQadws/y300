import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/application/forum_html_reader_preferences_controller.dart';
import 'package:y300/features/content_rendering_shared/application/forum_html_reader_preferences_repository_provider.dart';
import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';
import 'package:y300/features/content_rendering_shared/domain/repositories/forum_html_reader_preferences_repository.dart';
import 'package:y300/features/content_rendering_shared/presentation/widgets/forum_html_reader_settings_sheet.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/l10n/app_localizations.dart';

void main() {
  testWidgets('font draft stays immediate while body previews coalesce', (
    tester,
  ) async {
    final host = await _mount(tester);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ForumHtmlReaderSettingsSheet)),
    );
    expect(find.text(l10n.threadHtmlFontSize), findsOneWidget);

    _font(tester).onChanged!(1.2);
    await tester.pump();
    expect(host.preferences.typography.fontScale, 1.2);

    await tester.pump(const Duration(milliseconds: 20));
    _font(tester).onChanged!(1.4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    _font(tester).onChanged!(1.8);
    await tester.pump();

    expect(_font(tester).value, 1.8);
    expect(find.text('180%'), findsOneWidget);
    expect(host.preferences.typography.fontScale, 1.2);
    expect(host.changes, hasLength(1));
    expect(host.repository.saved, isEmpty);

    await tester.pump(const Duration(milliseconds: 49));
    expect(host.preferences.typography.fontScale, 1.2);
    await tester.pump(const Duration(milliseconds: 1));
    expect(host.preferences.typography.fontScale, 1.8);
    expect(host.changes, hasLength(2));
    expect(host.repository.saved, isEmpty);
    await host.dismiss(tester);
  });

  testWidgets('releasing line spacing publishes and saves the final draft', (
    tester,
  ) async {
    final host = await _mount(tester);
    _lineHeight(tester).onChanged!(1.8);
    await tester.pump();
    _lineHeight(tester).onChanged!(2.1);
    await tester.pump();

    expect(_lineHeight(tester).value, 2.1);
    expect(host.preferences.typography.lineHeightScale, 1.8);
    expect(host.repository.saved, isEmpty);

    _lineHeight(tester).onChangeEnd!(2.1);
    expect(host.preferences.typography.lineHeightScale, 2.1);
    await tester.pump();
    expect(host.repository.saved, hasLength(1));
    expect(host.repository.saved.single, host.preferences);
    expect(host.preferences.typography.fontScale, 1.15);

    await tester.pump(const Duration(milliseconds: 600));
    await host.dismiss(tester);
    expect(host.repository.saved, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing without a drag end saves the pending final draft', (
    tester,
  ) async {
    final host = await _mount(tester);
    _font(tester).onChanged!(1.3);
    await tester.pump();
    _font(tester).onChanged!(1.7);
    await tester.pump();
    expect(host.preferences.typography.fontScale, 1.3);
    expect(host.repository.saved, isEmpty);

    await host.dismiss(tester);
    expect(host.preferences.typography.fontScale, 1.7);
    expect(host.repository.saved, hasLength(1));
    expect(host.repository.saved.single.typography.fontScale, 1.7);
    await tester.pump(const Duration(milliseconds: 600));
    expect(host.repository.saved, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading disables controls and preserves the loaded flags', (
    tester,
  ) async {
    final loaded = ForumHtmlReaderPreferences.defaults().copyWith(
      typography: ForumHtmlReaderPreferences.defaults().typography.copyWith(
        fontScale: 1.35,
        lineHeightScale: 1.8,
      ),
      conversionMode: TextConversionMode.toTraditional,
      preserveAuthorFontSize: false,
    );
    final completion = Completer<ForumHtmlReaderPreferences>();
    final repository = _Repository(loadFuture: completion.future);
    final host = await _mount(tester, repository: repository, awaitLoad: false);

    expect(_font(tester).onChanged, isNull);
    expect(_font(tester).onChangeEnd, isNull);
    expect(_lineHeight(tester).onChanged, isNull);
    expect(_lineHeight(tester).onChangeEnd, isNull);
    expect(_authorSwitch(tester).onChanged, isNull);
    expect(_reset(tester).onPressed, isNull);
    expect(_conversion(tester).onSelectionChanged, isNull);
    expect(repository.saved, isEmpty);

    completion.complete(loaded);
    await tester.pump();
    await tester.pump();
    expect(host.preferences, loaded);
    expect(_font(tester).value, 1.35);
    expect(_lineHeight(tester).value, 1.8);
    expect(_authorSwitch(tester).value, isFalse);
    expect(_conversion(tester).selected, {TextConversionMode.toTraditional});

    _font(tester).onChanged!(1.5);
    _font(tester).onChangeEnd!(1.5);
    await tester.pump();
    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.conversionMode, loaded.conversionMode);
    expect(repository.saved.single.preserveAuthorFontSize, isFalse);
    await host.dismiss(tester);
  });

  testWidgets('reset retires a queued draft before its timers can apply it', (
    tester,
  ) async {
    final initial = ForumHtmlReaderPreferences.defaults().copyWith(
      conversionMode: TextConversionMode.toTraditional,
      preserveAuthorFontSize: false,
    );
    final host = await _mount(
      tester,
      repository: _Repository(initial: initial),
    );
    _font(tester).onChanged!(1.4);
    await tester.pump();
    _font(tester).onChanged!(1.9);
    await tester.pump();
    expect(_font(tester).value, 1.9);
    expect(host.preferences.typography.fontScale, 1.4);

    _reset(tester).onPressed!();
    await tester.pump();
    expect(host.preferences, ForumHtmlReaderPreferences.defaults());
    expect(_font(tester).value, 1.15);
    expect(host.repository.saved, [ForumHtmlReaderPreferences.defaults()]);

    await tester.pump(const Duration(milliseconds: 600));
    await host.dismiss(tester);
    expect(host.preferences, ForumHtmlReaderPreferences.defaults());
    expect(host.repository.saved, [ForumHtmlReaderPreferences.defaults()]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reset clears a local draft even when the provider is already at defaults',
    (tester) async {
      final host = await _mount(tester);
      _font(tester).onChanged!(1.3);
      await tester.pump();
      _font(tester).onChanged!(1.15);
      await tester.pump(const Duration(milliseconds: 90));
      expect(host.preferences, ForumHtmlReaderPreferences.defaults());
      _font(tester).onChanged!(1.8);
      await tester.pump();
      expect(_font(tester).value, 1.8);
      _reset(tester).onPressed!();
      await tester.pump();
      expect(_font(tester).value, 1.15);
      await tester.pump(const Duration(milliseconds: 600));
      await host.dismiss(tester);
      expect(host.preferences, ForumHtmlReaderPreferences.defaults());
      expect(host.repository.saved, isEmpty);
    },
  );

  testWidgets(
    '26 continuous slider ticks publish seven previews and one save',
    (tester) async {
      final host = await _mount(tester);

      for (var tick = 0; tick < 26; tick++) {
        _font(tester).onChanged!(0.75 + tick * 0.05);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(_font(tester).value, 2.0);
      expect(host.repository.saved, isEmpty);
      _font(tester).onChangeEnd!(2.0);
      await tester.pump();

      expect(host.changes, hasLength(7));
      expect(host.preferences.typography.fontScale, 2.0);
      expect(host.repository.saved, hasLength(1));
      expect(host.repository.saved.single, host.preferences);
      await host.dismiss(tester);
      expect(host.repository.saved, hasLength(1));
    },
  );
}

Slider _font(WidgetTester tester) =>
    _slider(tester, const Key('forum-html-reader-font-scale-slider'));

Slider _lineHeight(WidgetTester tester) =>
    _slider(tester, const Key('forum-html-reader-line-height-slider'));

Slider _slider(WidgetTester tester, Key key) => tester.widget<Slider>(
  find.descendant(of: find.byKey(key), matching: find.byType(Slider)),
);

SwitchListTile _authorSwitch(WidgetTester tester) =>
    tester.widget<SwitchListTile>(
      find.byKey(const Key('forum-html-reader-preserve-font-size-switch')),
    );

TextButton _reset(WidgetTester tester) => tester.widget<TextButton>(
  find.byKey(const Key('forum-html-reader-reset-button')),
);

SegmentedButton<TextConversionMode> _conversion(WidgetTester tester) =>
    tester.widget<SegmentedButton<TextConversionMode>>(
      find.byKey(const Key('forum-html-reader-conversion-mode-control')),
    );

Future<_Host> _mount(
  WidgetTester tester, {
  _Repository? repository,
  bool awaitLoad = true,
}) async {
  final host = _Host(repository ?? _Repository());
  addTearDown(host.container.dispose);
  if (awaitLoad) {
    await host.container.read(
      forumHtmlReaderPreferencesControllerProvider.future,
    );
  }
  host.container.listen(forumHtmlReaderPreferencesControllerProvider, (
    previous,
    next,
  ) {
    if (previous?.value != null &&
        next.value != null &&
        previous!.value != next.value) {
      host.changes.add(next.value!);
    }
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: host.container,
      child: MaterialApp(
        navigatorKey: host.navigator,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open-settings'),
              onPressed: () {
                unawaited(
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    sheetAnimationStyle: AnimationStyle.noAnimation,
                    builder: (_) => const ForumHtmlReaderSettingsSheet(
                      showConversionControls: true,
                    ),
                  ),
                );
              },
              child: const Icon(Icons.settings),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-settings')));
  await tester.pumpAndSettle();
  return host;
}

class _Host {
  _Host(this.repository)
    : container = ProviderContainer(
        overrides: [
          forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
      );

  final _Repository repository;
  final ProviderContainer container;
  final navigator = GlobalKey<NavigatorState>();
  final changes = <ForumHtmlReaderPreferences>[];

  ForumHtmlReaderPreferences get preferences =>
      container.read(forumHtmlReaderPreferencesControllerProvider).value!;

  Future<void> dismiss(WidgetTester tester) async {
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ForumHtmlReaderSettingsSheet), findsNothing);
  }
}

class _Repository implements ForumHtmlReaderPreferencesRepository {
  _Repository({ForumHtmlReaderPreferences? initial, this.loadFuture})
    : current = initial ?? ForumHtmlReaderPreferences.defaults();

  ForumHtmlReaderPreferences current;
  final Future<ForumHtmlReaderPreferences>? loadFuture;
  final saved = <ForumHtmlReaderPreferences>[];

  @override
  Future<ForumHtmlReaderPreferences> load() async {
    return current = await (loadFuture ?? Future.value(current));
  }

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    current = preferences;
    saved.add(preferences);
  }
}
