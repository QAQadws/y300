import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../domain/models/font_identity.dart';
import '../../domain/models/font_library_failure.dart';
import '../../domain/models/imported_font.dart';
import '../../domain/services/font_runtime_loader.dart';

typedef RegisterEngineFont = Future<void> Function(
  Uint8List bytes,
  String family,
);

/// Engine registration is append-only: deletion retires persistent references,
/// while already registered typefaces remain owned by the Flutter engine.
final class FlutterFontRuntimeLoader implements FontRuntimeLoader {
  FlutterFontRuntimeLoader({RegisterEngineFont? registerFont})
    : _registerFont = registerFont ?? _register;

  final RegisterEngineFont _registerFont;
  final Map<String, Future<String>> _registrations = {};

  @override
  Future<String> load(ImportedFont font, Uint8List bytes) {
    if (!FontIdentity.isImported(font.id) || bytes.length != font.byteLength) {
      return Future.error(
        const FontLibraryException(FontLibraryFailure.invalidFont),
      );
    }
    return _registrations.putIfAbsent(font.id, () => _load(font, bytes));
  }

  Future<String> _load(ImportedFont font, Uint8List bytes) async {
    final family = FontIdentity.runtimeFamily(font.id);
    try {
      // The caller verifies SFNT structure and digest first. Engine completion
      // alone is not proof of validity: some malformed fonts silently fall back.
      await Future<void>.sync(() => _registerFont(bytes, family));
      return family;
    } catch (_) {
      _registrations.remove(font.id);
      throw const FontLibraryException(FontLibraryFailure.loadFailed);
    }
  }

  static Future<void> _register(Uint8List bytes, String family) =>
      ui.loadFontFromList(bytes, fontFamily: family);
}
