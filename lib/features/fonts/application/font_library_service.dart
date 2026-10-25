import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../domain/models/font_identity.dart';
import '../domain/models/font_library_failure.dart';
import '../domain/models/font_resolution.dart';
import '../domain/models/imported_font.dart';
import '../domain/models/resolved_font.dart';
import '../domain/repositories/font_library_repository.dart';
import '../domain/services/font_file_validator.dart';
import '../domain/services/font_runtime_loader.dart';

/// Shared font operations. Scene-specific selections remain owned by readers.
final class FontLibraryService {
  FontLibraryService({
    required FontLibraryRepository repository,
    required FontRuntimeLoader runtimeLoader,
    FontFileValidator validator = const FontFileValidator(),
  }) : _repository = repository,
       _runtimeLoader = runtimeLoader,
       _validator = validator;

  final FontLibraryRepository _repository;
  final FontRuntimeLoader _runtimeLoader;
  final FontFileValidator _validator;
  final Map<String, int> _retirements = {};
  final Map<String, int> _pendingDeletions = {};
  final Map<String, Future<FontResolution>> _resolutions = {};
  Future<void> _mutations = Future<void>.value();
  bool _disposed = false;

  Stream<void> get changes => _repository.changes;

  Future<List<ImportedFont>> listFonts() {
    _ensureActive();
    return _repository.listFonts();
  }

  Future<ImportedFont> importFont({
    required String fileName,
    required Uint8List bytes,
  }) {
    _ensureActive();
    if (bytes.length > FontFileValidator.maxFontBytes) {
      return Future.error(
        const FontLibraryException(FontLibraryFailure.tooLarge),
      );
    }
    final snapshot = Uint8List.fromList(bytes);
    return _mutate(() async {
      final font = await _validate(fileName, snapshot, _validator);
      _ensureActive();
      await _runtimeLoader.load(font, snapshot);
      _ensureActive();
      // A rejected runtime load never publishes a persistent library entry.
      return _repository.importFont(fileName: fileName, bytes: snapshot);
    });
  }

  Future<void> deleteFont(String fontId) {
    _ensureActive();
    if (!FontIdentity.isImported(fontId)) {
      return Future.error(
        const FontLibraryException(FontLibraryFailure.notFound),
      );
    }
    // Retire already pending resolutions before waiting for an older import.
    _retirements.update(fontId, (value) => value + 1, ifAbsent: () => 1);
    _pendingDeletions.update(fontId, (value) => value + 1, ifAbsent: () => 1);
    return _mutate(() => _repository.deleteFont(fontId)).whenComplete(() {
      final remaining = _pendingDeletions[fontId]! - 1;
      if (remaining == 0) {
        _pendingDeletions.remove(fontId);
      } else {
        _pendingDeletions[fontId] = remaining;
      }
    });
  }

  Future<FontResolution> resolveFont(String? fontId) {
    final id = fontId == null || fontId.isEmpty ? FontIdentity.system : fontId;
    if (id == FontIdentity.system) {
      return Future.value(
        const FontResolution(
          requestedId: FontIdentity.system,
          font: ResolvedFont.system,
        ),
      );
    }
    if (!FontIdentity.isImported(id) || _pendingDeletions.containsKey(id)) {
      return Future.value(_fallback(id, FontLibraryFailure.notFound));
    }
    final retirement = _retirements[id] ?? 0;
    final key = '$id:$retirement';
    return _resolutions.putIfAbsent(key, () async {
      try {
        return await _resolve(id, retirement);
      } finally {
        _resolutions.remove(key);
      }
    });
  }

  Future<FontResolution> _resolve(String id, int retirement) async {
    try {
      _ensureActive();
      final font = _find(await _repository.listFonts(), id);
      if (font == null) return _fallback(id, FontLibraryFailure.notFound);
      final bytes = await _repository.readFont(id);
      _ensureActive();
      final family = await _runtimeLoader.load(font, bytes);
      _ensureActive();
      final current = _find(await _repository.listFonts(), id);
      if (current == null ||
          _pendingDeletions.containsKey(id) ||
          (_retirements[id] ?? 0) != retirement) {
        return _fallback(id, FontLibraryFailure.notFound);
      }
      _ensureActive();
      return FontResolution(
        requestedId: id,
        font: ResolvedFont(id: id, fontFamily: family),
      );
    } on FontLibraryException catch (error) {
      return _fallback(id, error.code);
    } catch (_) {
      return _fallback(id, FontLibraryFailure.loadFailed);
    }
  }

  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _mutations.then((_) {
      _ensureActive();
      return action();
    });
    _mutations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _ensureActive() {
    if (_disposed) {
      throw const FontLibraryException(FontLibraryFailure.loadFailed);
    }
  }

  void dispose() {
    _disposed = true;
  }

  static ImportedFont? _find(List<ImportedFont> fonts, String id) {
    for (final font in fonts) {
      if (font.id == id) return font;
    }
    return null;
  }

  // Keep isolate closures away from the service's repository/Future context.
  static Future<ImportedFont> _validate(
    String fileName,
    Uint8List bytes,
    FontFileValidator validator,
  ) => Isolate.run(() => validator.validate(fileName: fileName, bytes: bytes));

  static FontResolution _fallback(String id, FontLibraryFailure failure) =>
      FontResolution(
        requestedId: id,
        font: ResolvedFont.system,
        failure: failure,
      );
}
