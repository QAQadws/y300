import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_repository.dart';
import 'package:y300/features/fonts/domain/services/font_import_picker.dart';
import 'package:y300/features/fonts/domain/services/font_runtime_loader.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_display_settings_sheet.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';

const _font = ImportedFont(
  id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  displayName: 'Reading',
  storageFileName:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.ttf',
  byteLength: 1,
);

void main() {
  late FontLibraryService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    service = FontLibraryService(
      repository: _FontRepository(),
      runtimeLoader: _FontRuntime(),
    );
  });

  tearDown(() => service.dispose());

  testWidgets(
    'font row opens shared selector and emits only confirmed content ID',
    (tester) async {
      final changed = <NovelReaderPreferences>[];
      await _pump(tester, service: service, onChanged: changed.add);
      final strings = _strings(tester);
      expect(find.text(strings.fontSelectorSystemDefault), findsOneWidget);

      await _open(tester);
      await tester.tap(find.byKey(Key('body-font-item-${_font.id}')));
      await tester.pumpAndSettle();
      expect(changed, isEmpty);
      final preview = tester.widget<Text>(
        find.byKey(const Key('body-font-preview')),
      );
      expect(preview.style?.fontFamily, FontIdentity.runtimeFamily(_font.id));
      expect(
        preview.style?.fontSize,
        NovelReaderPreferences.defaults().fontSize,
      );
      expect(
        preview.style?.height,
        NovelReaderPreferences.defaults().lineHeight,
      );
      expect(preview.style?.color, Colors.purple);

      await tester.tap(find.byKey(const Key('body-font-apply')));
      await tester.pumpAndSettle();
      expect(changed, hasLength(1));
      expect(changed.single.fontFamily, _font.id);
      expect(find.text(strings.novelCustomFont), findsOneWidget);
    },
  );

  testWidgets('picker preview uses metrics changed inside the open settings', (
    tester,
  ) async {
    final changed = <NovelReaderPreferences>[];
    await _pump(tester, service: service, onChanged: changed.add);
    final sizeSlider = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(const Key('novel-reader-font-size-slider')),
        matching: find.byType(Slider),
      ),
    );
    sizeSlider.onChanged!(25);
    final lineSlider = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(const Key('novel-reader-line-height-slider')),
        matching: find.byType(Slider),
      ),
    );
    lineSlider.onChanged!(1.9);
    await tester.pump();
    await _open(tester);
    await tester.tap(find.byKey(Key('body-font-item-${_font.id}')));
    await tester.pumpAndSettle();

    final preview = tester.widget<Text>(
      find.byKey(const Key('body-font-preview')),
    );
    expect(preview.style?.fontSize, 25);
    expect(preview.style?.height, closeTo(1.9, 0.0001));
    expect(preview.style?.color, Colors.purple);
    expect(preview.style?.fontFamily, FontIdentity.runtimeFamily(_font.id));
    expect(changed.last.fontSize, 25);
    expect(changed.last.lineHeight, closeTo(1.9, 0.0001));
  });

  testWidgets('cancel keeps the prior font and emits no preference change', (
    tester,
  ) async {
    final changed = <NovelReaderPreferences>[];
    await _pump(
      tester,
      service: service,
      initialPreferences: NovelReaderPreferences.defaults().copyWith(
        fontFamily: _font.id,
      ),
      onChanged: changed.add,
    );
    await _open(tester);
    await tester.tap(find.byKey(const Key('body-font-item-system')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('body-font-cancel')));
    await tester.pumpAndSettle();
    expect(changed, isEmpty);
    expect(find.text(_strings(tester).novelCustomFont), findsOneWidget);
  });

  testWidgets('confirming system font emits its stable default ID', (
    tester,
  ) async {
    final changed = <NovelReaderPreferences>[];
    await _pump(
      tester,
      service: service,
      initialPreferences: NovelReaderPreferences.defaults().copyWith(
        fontFamily: _font.id,
      ),
      onChanged: changed.add,
    );
    await _open(tester);
    await tester.tap(find.byKey(const Key('body-font-item-system')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('body-font-apply')));
    await tester.pumpAndSettle();
    expect(changed.single.fontFamily, FontIdentity.system);
    expect(
      find.text(_strings(tester).fontSelectorSystemDefault),
      findsOneWidget,
    );
  });

  testWidgets(
    'late picker confirmation cannot update a replacement settings owner',
    (tester) async {
      final first = <NovelReaderPreferences>[];
      final replacement = <NovelReaderPreferences>[];
      var onChanged = first.add;
      late StateSetter updateHost;
      await _pump(
        tester,
        service: service,
        onChanged: first.add,
        buildSheet: () => StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return NovelReaderDisplaySettingsSheet(
              initialPreferences: NovelReaderPreferences.defaults(),
              onPreferencesChanged: onChanged,
            );
          },
        ),
      );
      await _open(tester);
      await tester.tap(find.byKey(Key('body-font-item-${_font.id}')));
      await tester.pumpAndSettle();
      updateHost(() => onChanged = replacement.add);
      await tester.pump();
      await tester.tap(find.byKey(const Key('body-font-apply')));
      await tester.pumpAndSettle();
      expect(first, isEmpty);
      expect(replacement, isEmpty);
    },
  );

  testWidgets('late picker confirmation is ignored after settings disposal', (
    tester,
  ) async {
    final changed = <NovelReaderPreferences>[];
    var show = true;
    late StateSetter updateHost;
    await _pump(
      tester,
      service: service,
      onChanged: changed.add,
      buildSheet: () => StatefulBuilder(
        builder: (context, setState) {
          updateHost = setState;
          return show
              ? NovelReaderDisplaySettingsSheet(
                  initialPreferences: NovelReaderPreferences.defaults(),
                  onPreferencesChanged: changed.add,
                )
              : const SizedBox.shrink();
        },
      ),
    );
    await _open(tester);
    await tester.tap(find.byKey(Key('body-font-item-${_font.id}')));
    await tester.pumpAndSettle();
    updateHost(() => show = false);
    await tester.pump();
    await tester.tap(find.byKey(const Key('body-font-apply')));
    await tester.pumpAndSettle();
    expect(changed, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required FontLibraryService service,
  required ValueChanged<NovelReaderPreferences> onChanged,
  NovelReaderPreferences? initialPreferences,
  Widget Function()? buildSheet,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fontLibraryServiceProvider.overrideWithValue(service),
        fontImportPickerProvider.overrideWithValue(_FontPicker()),
      ],
      child: LocalizedTestApp(
        home: Scaffold(
          body:
              buildSheet?.call() ??
              NovelReaderDisplaySettingsSheet(
                initialPreferences:
                    initialPreferences ?? NovelReaderPreferences.defaults(),
                onPreferencesChanged: onChanged,
                fontPreviewStyle: const TextStyle(
                  fontSize: 22,
                  height: 1.8,
                  color: Colors.purple,
                ),
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('novel-reader-font-selector')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('body-font-selector')), findsOneWidget);
}

AppLocalizations _strings(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(NovelReaderDisplaySettingsSheet)),
);

final class _FontRepository implements FontLibraryRepository {
  @override
  Stream<void> get changes => const Stream<void>.empty();
  @override
  Future<List<ImportedFont>> listFonts() async => [_font];
  @override
  Future<Uint8List> readFont(String fontId) async => Uint8List(1);
  @override
  Future<void> dispose() async {}
  @override
  Future<void> deleteFont(String fontId) async {}
  @override
  Future<ImportedFont> importFont({
    required String fileName,
    required Uint8List bytes,
  }) async => _font;
}

final class _FontRuntime implements FontRuntimeLoader {
  @override
  Future<String> load(ImportedFont font, Uint8List bytes) async =>
      FontIdentity.runtimeFamily(font.id);
}

final class _FontPicker implements FontImportPicker {
  @override
  Future<FontImportFile?> pickFont() async => null;
}
