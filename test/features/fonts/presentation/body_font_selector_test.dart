import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/fonts/application/font_library_providers.dart';
import 'package:y300/features/fonts/application/font_library_service.dart';
import 'package:y300/features/fonts/domain/models/font_identity.dart';
import 'package:y300/features/fonts/domain/models/font_import_file.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/font_resolution.dart';
import 'package:y300/features/fonts/domain/models/imported_font.dart';
import 'package:y300/features/fonts/domain/models/resolved_font.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_repository.dart';
import 'package:y300/features/fonts/domain/services/font_import_picker.dart';
import 'package:y300/features/fonts/domain/services/font_runtime_loader.dart';
import 'package:y300/features/fonts/presentation/body_font_selector.dart';
import 'package:y300/features/fonts/presentation/font_selector_controller.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import 'font_selector_test_driver.dart';

void main() {
  late FontSelectorTestDriver driver;
  late FontSelectorController controller;

  setUp(() {
    driver = FontSelectorTestDriver();
    controller = driver.controller();
    addTearDown(controller.dispose);
    addTearDown(driver.dispose);
  });

  testWidgets(
    'previews the font with caller typography and cancel returns null',
    (tester) async {
      final result = <ResolvedFont?>[];
      await _open(tester, controller, results: result);
      final strings = _strings(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('body-font-list')),
          matching: find.text(strings.fontSelectorSystemDefault),
        ),
        findsOneWidget,
      );
      expect(find.text(strings.fontSelectorImport), findsOneWidget);
      expect(find.text(strings.fontSelectorSample), findsOneWidget);

      await tester.tap(find.byKey(Key('body-font-item-${selectorFontA.id}')));
      await tester.pumpAndSettle();
      final preview = tester.widget<Text>(
        find.byKey(const Key('body-font-preview')),
      );
      expect(
        preview.style?.fontFamily,
        FontIdentity.runtimeFamily(selectorFontA.id),
      );
      expect(preview.style?.fontSize, 19);
      expect(preview.style?.height, 1.7);
      expect(preview.style?.fontWeight, FontWeight.w600);
      expect(preview.style?.color, Colors.purple);

      await tester.tap(find.byKey(const Key('body-font-cancel')));
      await tester.pumpAndSettle();
      expect(result, [null]);
    },
  );

  testWidgets('system preview resets the family inherited from the caller', (
    tester,
  ) async {
    await _open(tester, controller);
    final preview = tester.widget<Text>(
      find.byKey(const Key('body-font-preview')),
    );
    expect(preview.style?.fontFamily, '');
    expect(preview.style?.fontFamilyFallback, isEmpty);
  });

  testWidgets('apply stays disabled until the chosen font is ready', (
    tester,
  ) async {
    final results = <ResolvedFont?>[];
    await _open(tester, controller, results: results);
    final pending = Completer<FontResolution>();
    driver.pendingResolutions[selectorFontA.id] = pending;
    await tester.tap(find.byKey(Key('body-font-item-${selectorFontA.id}')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('body-font-apply')))
          .onPressed,
      isNull,
    );

    pending.complete(selectorResolution(selectorFontA.id));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('body-font-apply')));
    await tester.pumpAndSettle();
    expect(results, [selectorResolution(selectorFontA.id).font]);
  });

  testWidgets('import selects the imported font only inside the draft', (
    tester,
  ) async {
    final results = <ResolvedFont?>[];
    await _open(tester, controller, results: results);
    await tester.tap(find.byKey(const Key('body-font-import')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('body-font-list')),
        matching: find.text(selectorImportedFont.displayName),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('body-font-preview-name'))).data,
      selectorImportedFont.displayName,
    );
    expect(controller.selectedFont.id, selectorImportedFont.id);
    expect(results, isEmpty);

    await tester.tap(find.byKey(const Key('body-font-cancel')));
    await tester.pumpAndSettle();
    expect(results, [null]);
    expect(driver.fonts, contains(selectorImportedFont));
  });

  testWidgets('deleting the selected font restores the system preview', (
    tester,
  ) async {
    await _open(tester, controller);
    await tester.tap(find.byKey(Key('body-font-item-${selectorFontA.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('body-font-delete-${selectorFontA.id}')));
    await tester.pumpAndSettle();
    expect(find.text(selectorFontA.displayName), findsNothing);
    expect(controller.selectedFont, ResolvedFont.system);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('body-font-preview')))
          .style
          ?.fontFamily,
      '',
    );
  });

  testWidgets(
    'retry after an initial read failure restores the requested font',
    (tester) async {
      driver.listFailure = FontLibraryFailure.storage;
      final retryController = driver.controller(
        initialFontId: selectorFontA.id,
      );
      addTearDown(retryController.dispose);
      await _open(tester, retryController);
      final strings = _strings(tester);
      expect(find.text(strings.fontSelectorStorageFailure), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('body-font-apply')))
            .onPressed,
        isNull,
      );

      driver.listFailure = null;
      await tester.tap(find.byKey(const Key('body-font-retry')));
      await tester.pumpAndSettle();
      expect(retryController.selectedFont.id, selectorFontA.id);
      expect(find.byKey(const Key('body-font-error')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('body-font-apply')))
            .onPressed,
        isNotNull,
      );
    },
  );

  for (final locale in [const Locale('zh'), const Locale('zh', 'TW')]) {
    testWidgets('keeps the large and small preview samples for $locale', (
      tester,
    ) async {
      await _open(tester, controller, locale: locale);
      final strings = _strings(tester);
      expect(find.text(strings.fontSelectorSample), findsOneWidget);
      expect(find.text(strings.fontSelectorGlyphSample), findsOneWidget);

      await tester.tap(find.byKey(Key('body-font-item-${selectorFontA.id}')));
      await tester.pumpAndSettle();
      final preview = tester.widget<Text>(
        find.byKey(const Key('body-font-preview')),
      );
      final glyphs = tester.widget<Text>(
        find.byKey(const Key('body-font-preview-glyphs')),
      );
      expect(glyphs.data, strings.fontSelectorGlyphSample);
      expect(
        glyphs.style?.fontFamily,
        FontIdentity.runtimeFamily(selectorFontA.id),
      );
      expect(glyphs.style!.fontSize, lessThan(preview.style!.fontSize!));
    });

    testWidgets(
      'an active font import exposes a localized loading label for $locale',
      (tester) async {
        final picking = Completer<void>();
        driver.onPick = () async {
          await picking.future;
          return null;
        };
        await _open(tester, controller, locale: locale);
        final strings = _strings(tester);
        await tester.tap(find.byKey(const Key('body-font-import')));
        await tester.pump();
        expect(
          tester
              .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator),
              )
              .semanticsLabel,
          strings.fontSelectorLoading,
        );
        picking.complete();
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('typed import failure is localized for $locale', (
      tester,
    ) async {
      driver.importFailure = FontLibraryFailure.invalidFont;
      await _open(tester, controller, locale: locale);
      final strings = _strings(tester);
      await tester.tap(find.byKey(const Key('body-font-import')));
      await tester.pumpAndSettle();
      expect(find.text(strings.fontSelectorInvalidFont), findsOneWidget);
      expect(controller.selectedFont, ResolvedFont.system);
      expect(find.text(strings.commonRetry), findsOneWidget);
    });
  }

  testWidgets('large text and a dark theme keep controls reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester, controller, dark: true, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('body-font-cancel')), findsOneWidget);
    expect(find.byKey(const Key('body-font-apply')), findsOneWidget);
    await tester.tap(find.byKey(const Key('body-font-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(BodyFontSelector), findsNothing);
  });

  testWidgets(
    'the sheet grows with its font list instead of reserving empty height',
    (tester) async {
      driver.fonts.clear();
      await _open(tester, controller);
      final selector = find.byKey(const Key('body-font-selector'));
      final emptyHeight = tester.getSize(selector).height;
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(emptyHeight, lessThan(screenHeight * 0.65));

      driver.fonts.addAll([selectorFontA, selectorFontB]);
      await controller.reload();
      await tester.pumpAndSettle();

      expect(tester.getSize(selector).height, greaterThan(emptyHeight));
      expect(
        find.byKey(Key('body-font-item-${selectorFontA.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('body-font-item-${selectorFontB.id}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a long library scrolls while the preview and actions stay visible',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      driver.fonts
        ..clear()
        ..addAll(
          List.generate(30, (index) {
            final id = index.toRadixString(16).padLeft(64, '0');
            return ImportedFont(
              id: id,
              displayName: 'library-$index.ttf',
              storageFileName: '$id.ttf',
              byteLength: 1024,
            );
          }),
        );
      await _open(tester, controller);
      final preview = find.byKey(const Key('body-font-preview'));
      final apply = find.byKey(const Key('body-font-apply'));
      final previewBefore = tester.getRect(preview);
      final applyBefore = tester.getRect(apply);
      await tester.scrollUntilVisible(
        find.byKey(Key('body-font-item-${driver.fonts.last.id}')),
        220,
        scrollable: find.descendant(
          of: find.byKey(const Key('body-font-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getRect(preview), previewBefore);
      expect(tester.getRect(apply), applyBefore);
      expect(apply.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('body-font-cancel')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the production sheet hides the handle even when the theme enables it',
    (tester) async {
      driver.fonts.clear();
      final service = FontLibraryService(
        repository: _HostFontRepository(driver),
        runtimeLoader: _UnusedRuntimeLoader(),
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fontLibraryServiceProvider.overrideWithValue(service),
            fontImportPickerProvider.overrideWithValue(_CancelledPicker()),
          ],
          child: LocalizedTestApp(
            theme: AppTheme.light().copyWith(
              bottomSheetTheme: const BottomSheetThemeData(
                showDragHandle: true,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('open-production-font-selector'),
                  onPressed: () => showBodyFontSelector(context: context),
                  child: const Icon(Icons.font_download_outlined),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-production-font-selector')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('body-font-cancel')));
      await tester.pumpAndSettle();
    },
  );
}

AppLocalizations _strings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BodyFontSelector)));

Future<void> _open(
  WidgetTester tester,
  FontSelectorController controller, {
  List<ResolvedFont?>? results,
  Locale locale = const Locale('zh'),
  bool dark = false,
  double textScale = 1,
}) async {
  await controller.initialize();
  await tester.pumpWidget(
    LocalizedTestApp(
      locale: locale,
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('open-font-selector'),
              onPressed: () async {
                final result = await showModalBottomSheet<ResolvedFont>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: false,
                  builder: (_) => BodyFontSelector(
                    controller: controller,
                    previewStyle: const TextStyle(
                      fontFamily: 'previous-custom-family',
                      fontFamilyFallback: ['previous-fallback'],
                      fontSize: 19,
                      height: 1.7,
                      fontWeight: FontWeight.w600,
                      color: Colors.purple,
                    ),
                  ),
                );
                results?.add(result);
              },
              child: const Icon(Icons.font_download_outlined),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-font-selector')));
  await tester.pumpAndSettle();
}

final class _HostFontRepository implements FontLibraryRepository {
  const _HostFontRepository(this.driver);

  final FontSelectorTestDriver driver;

  @override
  Stream<void> get changes => driver.changes.stream;

  @override
  Future<List<ImportedFont>> listFonts() => driver.listFonts();

  @override
  Future<ImportedFont> importFont({
    required String fileName,
    required Uint8List bytes,
  }) => driver.importFont(fileName: fileName, bytes: bytes);

  @override
  Future<void> deleteFont(String fontId) => driver.deleteFont(fontId);

  @override
  Future<Uint8List> readFont(String fontId) => throw UnimplementedError();

  @override
  Future<void> dispose() async {}
}

final class _UnusedRuntimeLoader implements FontRuntimeLoader {
  @override
  Future<String> load(ImportedFont font, Uint8List bytes) =>
      throw UnimplementedError();
}

final class _CancelledPicker implements FontImportPicker {
  @override
  Future<FontImportFile?> pickFont() async => null;
}
