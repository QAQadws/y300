import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_repository.dart';
import 'package:y300/features/fonts/domain/services/font_import_picker.dart';
import 'package:y300/features/fonts/domain/services/font_runtime_loader.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../../test_support/localized_test_app.dart';

const _font = ImportedFont(
  id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  displayName: 'Reading',
  storageFileName:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.ttf',
  byteLength: 1,
);

void main() {
  late _Preferences preferences;
  late FontLibraryService fonts;
  late ProviderContainer container;

  setUp(() {
    preferences = _Preferences();
    fonts = FontLibraryService(repository: _Fonts(), runtimeLoader: _Runtime());
    container = ProviderContainer(
      overrides: [
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          preferences,
        ),
        fontLibraryServiceProvider.overrideWithValue(fonts),
        fontImportPickerProvider.overrideWithValue(_Picker()),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    fonts.dispose();
  });

  testWidgets('the shared picker saves only a confirmed stable font ID', (
    tester,
  ) async {
    await _mount(tester, container);
    final strings = _strings(tester);
    expect(find.text(strings.fontSelectorSystemDefault), findsOneWidget);
    await _open(tester);
    await tester.tap(find.byKey(Key('body-font-item-${_font.id}')));
    await tester.pumpAndSettle();
    expect(preferences.saved, isEmpty);
    final sample = tester.widget<Text>(
      find.byKey(const Key('body-font-preview')),
    );
    expect(sample.style?.fontFamily, FontIdentity.runtimeFamily(_font.id));
    expect(sample.style?.fontSize, closeTo(14 * 1.15, 0.001));
    expect(sample.style?.height, 1.5);
    expect(sample.style?.color, Colors.purple);
    await tester.tap(find.byKey(const Key('body-font-apply')));
    await tester.pumpAndSettle();
    expect(preferences.current.fontFamily, _font.id);
    expect(preferences.saved.single.fontFamily, _font.id);
    expect(find.text(strings.fontSelectorCustomFont), findsOneWidget);
  });

  testWidgets('cancel leaves the shared reader preferences unchanged', (
    tester,
  ) async {
    await _mount(tester, container);
    final before = preferences.current;
    await _open(tester);
    await tester.tap(find.byKey(Key('body-font-item-${_font.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('body-font-cancel')));
    await tester.pumpAndSettle();
    expect(preferences.current, before);
    expect(preferences.saved, isEmpty);
  });

  testWidgets('system default can replace an imported font', (tester) async {
    preferences.current = preferences.current.copyWith(fontFamily: _font.id);
    await _mount(tester, container);
    await _open(tester);
    await tester.tap(find.byKey(const Key('body-font-item-system')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('body-font-apply')));
    await tester.pumpAndSettle();
    expect(preferences.current.fontFamily, FontIdentity.system);
    expect(preferences.saved.single.fontFamily, FontIdentity.system);
  });

  testWidgets('picker sample uses the latest slider draft metrics', (
    tester,
  ) async {
    await _mount(tester, container);
    _slider(tester, 'forum-html-reader-font-scale-slider').onChanged!(1.7);
    _slider(tester, 'forum-html-reader-line-height-slider').onChanged!(2.1);
    await tester.pump();
    await _open(tester);
    final sample = tester.widget<Text>(
      find.byKey(const Key('body-font-preview')),
    );
    expect(sample.style?.fontSize, closeTo(14 * 1.7, 0.001));
    expect(sample.style?.height, 2.1);
    expect(sample.style?.color, Colors.purple);
    await tester.tap(find.byKey(const Key('body-font-cancel')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('a disposed settings sheet cannot apply a late selection', (
    tester,
  ) async {
    var visible = true;
    late StateSetter update;
    await _mount(
      tester,
      container,
      buildSheet: () => StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return visible
              ? const ForumHtmlReaderSettingsSheet()
              : const SizedBox.shrink();
        },
      ),
    );
    await _open(tester);
    await tester.tap(find.byKey(Key('body-font-item-${_font.id}')));
    await tester.pumpAndSettle();
    update(() => visible = false);
    await tester.pump();
    await tester.tap(find.byKey(const Key('body-font-apply')));
    await tester.pumpAndSettle();
    expect(preferences.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reloaded settings owner rejects the previous picker result', (
    tester,
  ) async {
    await _mount(tester, container);
    await _open(tester);
    await tester.tap(find.byKey(Key('body-font-item-${_font.id}')));
    await tester.pumpAndSettle();
    final loading = Completer<ForumHtmlReaderPreferences>();
    preferences.nextLoad = loading.future;
    container.invalidate(forumHtmlReaderPreferencesControllerProvider);
    await tester.pump();
    loading.complete(ForumHtmlReaderPreferences.defaults());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('body-font-apply')));
    await tester.pumpAndSettle();
    expect(preferences.saved, isEmpty);
    expect(preferences.current.fontFamily, FontIdentity.system);
  });

  testWidgets('a failed font save rolls back and shows localized feedback', (
    tester,
  ) async {
    await _mount(tester, container);
    final strings = _strings(tester);
    preferences.rejectWrites = true;
    await _open(tester);
    await tester.tap(find.byKey(Key('body-font-item-${_font.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('body-font-apply')));
    await tester.pumpAndSettle();
    expect(preferences.current.fontFamily, FontIdentity.system);
    expect(
      container
          .read(forumHtmlReaderPreferencesControllerProvider)
          .value!
          .fontFamily,
      FontIdentity.system,
    );
    expect(find.text(strings.fontSelectorStorageFailure), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(
  WidgetTester tester,
  ProviderContainer container, {
  Widget Function()? buildSheet,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: LocalizedTestApp(
        home: Scaffold(
          body:
              buildSheet?.call() ??
              const ForumHtmlReaderSettingsSheet(
                fontPreviewStyle: TextStyle(color: Colors.purple),
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('forum-html-reader-font-family')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('body-font-selector')), findsOneWidget);
}

Slider _slider(WidgetTester tester, String key) => tester.widget<Slider>(
  find.descendant(of: find.byKey(Key(key)), matching: find.byType(Slider)),
);

AppLocalizations _strings(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(ForumHtmlReaderSettingsSheet)),
);

final class _Preferences implements ForumHtmlReaderPreferencesRepository {
  ForumHtmlReaderPreferences current = ForumHtmlReaderPreferences.defaults();
  Future<ForumHtmlReaderPreferences>? nextLoad;
  bool rejectWrites = false;
  final saved = <ForumHtmlReaderPreferences>[];

  @override
  Future<ForumHtmlReaderPreferences> load() async {
    final pending = nextLoad;
    nextLoad = null;
    return current = pending == null ? current : await pending;
  }

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    if (rejectWrites) throw StateError('private storage diagnostics');
    current = preferences;
    saved.add(preferences);
  }
}

final class _Fonts implements FontLibraryRepository {
  @override
  Stream<void> get changes => const Stream<void>.empty();
  @override
  Future<List<ImportedFont>> listFonts() async => [_font];
  @override
  Future<Uint8List> readFont(String fontId) async => Uint8List(1);
  @override
  Future<void> deleteFont(String fontId) async {}
  @override
  Future<ImportedFont> importFont({
    required String fileName,
    required Uint8List bytes,
  }) async => _font;
  @override
  Future<void> dispose() async {}
}

final class _Runtime implements FontRuntimeLoader {
  @override
  Future<String> load(ImportedFont font, Uint8List bytes) async =>
      FontIdentity.runtimeFamily(font.id);
}

final class _Picker implements FontImportPicker {
  @override
  Future<FontImportFile?> pickFont() async => null;
}
