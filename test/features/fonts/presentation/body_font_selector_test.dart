import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/fonts/domain/models/font_identity.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/font_resolution.dart';
import 'package:y300/features/fonts/domain/models/resolved_font.dart';
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
      expect(find.text(strings.fontSelectorSystemDefault), findsOneWidget);
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
    expect(find.text(selectorImportedFont.displayName), findsOneWidget);
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
