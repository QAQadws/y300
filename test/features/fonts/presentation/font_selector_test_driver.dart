import 'dart:async';
import 'dart:typed_data';

import 'package:y300/features/fonts/domain/models/font_identity.dart';
import 'package:y300/features/fonts/domain/models/font_import_file.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/font_resolution.dart';
import 'package:y300/features/fonts/domain/models/imported_font.dart';
import 'package:y300/features/fonts/domain/models/resolved_font.dart';
import 'package:y300/features/fonts/presentation/font_selector_controller.dart';

const selectorFontA = ImportedFont(
  id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  displayName: 'font-a.ttf',
  storageFileName: 'a.ttf',
  byteLength: 1024,
);
const selectorFontB = ImportedFont(
  id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  displayName: 'font-b.otf',
  storageFileName: 'b.otf',
  byteLength: 2048,
);
const selectorImportedFont = ImportedFont(
  id: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  displayName: 'imported.ttf',
  storageFileName: 'c.ttf',
  byteLength: 512,
);

FontResolution selectorResolution(String id) => FontResolution(
  requestedId: id,
  font: id == FontIdentity.system
      ? ResolvedFont.system
      : ResolvedFont(id: id, fontFamily: FontIdentity.runtimeFamily(id)),
);

final class FontSelectorTestDriver {
  final fonts = <ImportedFont>[selectorFontA, selectorFontB];
  final changes = StreamController<void>.broadcast(sync: true);
  final pendingResolutions = <String, Completer<FontResolution>>{};
  final requestedIds = <String?>[];
  FontLibraryFailure? listFailure;
  FontLibraryFailure? importFailure;
  FontLibraryFailure? deleteFailure;
  Future<FontImportFile?> Function()? onPick;
  int importCalls = 0;
  int deleteCalls = 0;
  int listCalls = 0;

  FontSelectorController controller({String? initialFontId}) =>
      FontSelectorController(
        listFonts: listFonts,
        resolveFont: resolveFont,
        importFont: importFont,
        deleteFont: deleteFont,
        pickFont: pickFont,
        initialFontId: initialFontId,
        changes: changes.stream,
      );

  Future<List<ImportedFont>> listFonts() async {
    listCalls++;
    if (listFailure case final failure?) {
      throw FontLibraryException(failure);
    }
    return List.of(fonts);
  }

  Future<FontResolution> resolveFont(String? requestedId) async {
    requestedIds.add(requestedId);
    final id = requestedId ?? FontIdentity.system;
    if (pendingResolutions[id] case final pending?) return pending.future;
    if (id == FontIdentity.system || fonts.any((font) => font.id == id)) {
      return selectorResolution(id);
    }
    return FontResolution(
      requestedId: id,
      font: ResolvedFont.system,
      failure: FontLibraryFailure.notFound,
    );
  }

  Future<FontImportFile?> pickFont() async => onPick != null
      ? onPick!()
      : FontImportFile(
          fileName: selectorImportedFont.displayName,
          bytes: Uint8List.fromList([1, 2, 3]),
        );

  Future<ImportedFont> importFont({
    required String fileName,
    required Uint8List bytes,
  }) async {
    importCalls++;
    if (importFailure case final failure?) {
      throw FontLibraryException(failure);
    }
    if (!fonts.contains(selectorImportedFont)) fonts.add(selectorImportedFont);
    changes.add(null);
    return selectorImportedFont;
  }

  Future<void> deleteFont(String id) async {
    deleteCalls++;
    if (deleteFailure case final failure?) {
      throw FontLibraryException(failure);
    }
    fonts.removeWhere((font) => font.id == id);
    changes.add(null);
  }

  Future<void> dispose() => changes.close();
}
