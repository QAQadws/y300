import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/fonts/domain/models/font_import_file.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/font_resolution.dart';
import 'package:y300/features/fonts/domain/models/resolved_font.dart';

import 'font_selector_test_driver.dart';

void main() {
  late FontSelectorTestDriver driver;

  setUp(() {
    driver = FontSelectorTestDriver();
    addTearDown(driver.dispose);
  });

  test('initial selection must resolve before it can be confirmed', () async {
    final pending = Completer<FontResolution>();
    driver.pendingResolutions[selectorFontA.id] = pending;
    final controller = driver.controller(initialFontId: selectorFontA.id);
    addTearDown(controller.dispose);
    final initialization = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.isResolving, isTrue);
    expect(controller.canConfirm, isFalse);

    pending.complete(selectorResolution(selectorFontA.id));
    await initialization;
    expect(controller.selectedFont.id, selectorFontA.id);
    expect(controller.canConfirm, isTrue);
  });

  test('newer selection supersedes an older pending font load', () async {
    final controller = driver.controller();
    addTearDown(controller.dispose);
    await controller.initialize();
    final pendingA = Completer<FontResolution>();
    driver.pendingResolutions[selectorFontA.id] = pendingA;

    final oldSelection = controller.selectFont(selectorFontA.id);
    expect(controller.canConfirm, isFalse);
    await controller.selectFont(selectorFontB.id);
    expect(controller.selectedFont.id, selectorFontB.id);

    pendingA.complete(selectorResolution(selectorFontA.id));
    await oldSelection;
    expect(controller.selectedFont.id, selectorFontB.id);
    expect(controller.requestedFontId, selectorFontB.id);
    expect(controller.canConfirm, isTrue);
  });

  test('missing initial font becomes an explicit system fallback', () async {
    final controller = driver.controller(initialFontId: 'missing-font');
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(controller.selectedFont, ResolvedFont.system);
    expect(controller.failure, FontLibraryFailure.notFound);
    expect(await controller.confirmSelection(), ResolvedFont.system);
  });

  test(
    'a transient list failure retains the usable list and selection',
    () async {
      final controller = driver.controller(initialFontId: selectorFontA.id);
      addTearDown(controller.dispose);
      await controller.initialize();
      driver.listFailure = FontLibraryFailure.storage;

      expect(await controller.reload(), isFalse);
      expect(controller.fonts, [selectorFontA, selectorFontB]);
      expect(controller.selectedFont.id, selectorFontA.id);
      expect(controller.failure, FontLibraryFailure.storage);

      driver.listFailure = null;
      expect(await controller.reload(), isTrue);
      expect(controller.failure, isNull);
    },
  );

  test(
    'failed initial catalog cannot silently confirm a different font',
    () async {
      driver.listFailure = FontLibraryFailure.corruptLibrary;
      final controller = driver.controller(initialFontId: selectorFontA.id);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(controller.canConfirm, isFalse);
      expect(await controller.confirmSelection(), isNull);
      await controller.selectFont('system');
      expect(await controller.confirmSelection(), ResolvedFont.system);
    },
  );

  test(
    'retry resolves the original draft after an initial catalog failure',
    () async {
      driver.listFailure = FontLibraryFailure.storage;
      final controller = driver.controller(initialFontId: selectorFontA.id);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.canConfirm, isFalse);

      driver.listFailure = null;
      await controller.retry();
      expect(controller.fonts, [selectorFontA, selectorFontB]);
      expect(controller.selectedFont.id, selectorFontA.id);
      expect(controller.canConfirm, isTrue);
      expect(controller.failure, isNull);
    },
  );

  test('picker cancellation preserves selection and does not import', () async {
    driver.onPick = () async => null;
    final controller = driver.controller(initialFontId: selectorFontA.id);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.importFont();

    expect(driver.importCalls, 0);
    expect(controller.selectedFont.id, selectorFontA.id);
    expect(controller.isImporting, isFalse);
  });

  test(
    'late picker result after dispose cannot start a library write',
    () async {
      final selectedFile = await driver.pickFont();
      final pending = Completer<FontImportFile?>();
      driver.onPick = () => pending.future;
      final controller = driver.controller();
      await controller.initialize();
      final importing = controller.importFont();
      controller.dispose();

      pending.complete(selectedFile);
      await importing;
      expect(driver.importCalls, 0);
    },
  );

  test(
    'successful import refreshes the library and resolves the new draft',
    () async {
      final controller = driver.controller(initialFontId: selectorFontA.id);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.importFont();

      expect(driver.importCalls, 1);
      expect(controller.fonts, contains(selectorImportedFont));
      expect(controller.selectedFont.id, selectorImportedFont.id);
      expect(controller.canConfirm, isTrue);
    },
  );

  test('import failure keeps the previous resolved selection', () async {
    driver.importFailure = FontLibraryFailure.invalidFont;
    final controller = driver.controller(initialFontId: selectorFontA.id);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.importFont();

    expect(controller.selectedFont.id, selectorFontA.id);
    expect(controller.failure, FontLibraryFailure.invalidFont);
    expect(controller.fonts, [selectorFontA, selectorFontB]);
  });

  test('deleting a pending selection retires its late load result', () async {
    final controller = driver.controller();
    addTearDown(controller.dispose);
    await controller.initialize();
    final pending = Completer<FontResolution>();
    driver.pendingResolutions[selectorFontA.id] = pending;
    final selecting = controller.selectFont(selectorFontA.id);

    await controller.deleteFont(selectorFontA.id);
    expect(controller.selectedFont, ResolvedFont.system);
    pending.complete(selectorResolution(selectorFontA.id));
    await selecting;
    expect(controller.selectedFont, ResolvedFont.system);
    expect(controller.canConfirm, isTrue);
  });

  test('deletion failure retains the font and selected draft', () async {
    driver.deleteFailure = FontLibraryFailure.storage;
    final controller = driver.controller(initialFontId: selectorFontA.id);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.deleteFont(selectorFontA.id);

    expect(controller.selectedFont.id, selectorFontA.id);
    expect(controller.fonts, contains(selectorFontA));
    expect(controller.failure, FontLibraryFailure.storage);
    expect(controller.deletingFontId, isNull);
  });

  test('confirmation revalidates a font removed after its preview', () async {
    final controller = driver.controller(initialFontId: selectorFontA.id);
    addTearDown(controller.dispose);
    await controller.initialize();
    driver.fonts.remove(selectorFontA);

    expect(await controller.confirmSelection(), isNull);
    expect(controller.selectedFont, ResolvedFont.system);
    expect(controller.failure, FontLibraryFailure.notFound);
    expect(await controller.confirmSelection(), ResolvedFont.system);
  });

  test(
    'library changes retire an externally removed pending selection',
    () async {
      final controller = driver.controller();
      addTearDown(controller.dispose);
      await controller.initialize();
      final pending = Completer<FontResolution>();
      driver.pendingResolutions[selectorFontA.id] = pending;
      final selecting = controller.selectFont(selectorFontA.id);
      driver.fonts.remove(selectorFontA);
      driver.changes.add(null);
      await Future<void>.delayed(Duration.zero);

      pending.complete(selectorResolution(selectorFontA.id));
      await selecting;
      expect(controller.selectedFont, ResolvedFont.system);
      expect(controller.failure, FontLibraryFailure.notFound);
      expect(controller.canConfirm, isTrue);
    },
  );
}
