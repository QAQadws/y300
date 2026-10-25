import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:y300/features/fonts/domain/models/font_identity.dart';
import 'package:y300/features/fonts/domain/models/font_import_file.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/font_resolution.dart';
import 'package:y300/features/fonts/domain/models/imported_font.dart';
import 'package:y300/features/fonts/domain/models/resolved_font.dart';

typedef FontSelectorImport = Future<ImportedFont> Function({
  required String fileName,
  required Uint8List bytes,
});

/// A dialog-local draft. Library mutations take effect immediately; the caller
/// receives a scene preference only after confirming the resolved selection.
final class FontSelectorController extends ChangeNotifier {
  FontSelectorController({
    required Future<List<ImportedFont>> Function() listFonts,
    required Future<FontResolution> Function(String? id) resolveFont,
    required FontSelectorImport importFont,
    required Future<void> Function(String id) deleteFont,
    required Future<FontImportFile?> Function() pickFont,
    String? initialFontId,
    Stream<void>? changes,
  }) : _listFonts = listFonts,
       _resolveFont = resolveFont,
       _importFont = importFont,
       _deleteFont = deleteFont,
       _pickFont = pickFont,
       _initialFontId = initialFontId {
    _subscription = changes?.listen((_) {
      if (_isMutating) {
        _reloadPending = true;
      } else if (!_disposed) {
        unawaited(reload());
      }
    });
  }

  final Future<List<ImportedFont>> Function() _listFonts;
  final Future<FontResolution> Function(String? id) _resolveFont;
  final FontSelectorImport _importFont;
  final Future<void> Function(String id) _deleteFont;
  final Future<FontImportFile?> Function() _pickFont;
  final String? _initialFontId;
  StreamSubscription<void>? _subscription;

  List<ImportedFont> _fonts = const [];
  ResolvedFont _selectedFont = ResolvedFont.system;
  String _requestedFontId = FontIdentity.system;
  FontLibraryFailure? _failure;
  bool _initialized = false;
  bool _disposed = false;
  bool _isLoading = false;
  bool _isResolving = false;
  bool _isImporting = false;
  bool _isConfirming = false;
  bool _hasResolvedSelection = false;
  bool _reloadPending = false;
  String? _deletingFontId;
  int _catalogGeneration = 0;
  int _selectionGeneration = 0;
  int _mutationGeneration = 0;

  List<ImportedFont> get fonts => _fonts;
  ResolvedFont get selectedFont => _selectedFont;
  String get requestedFontId => _requestedFontId;
  FontLibraryFailure? get failure => _failure;
  bool get isLoading => _isLoading;
  bool get isResolving => _isResolving;
  bool get isImporting => _isImporting;
  bool get isConfirming => _isConfirming;
  String? get deletingFontId => _deletingFontId;
  bool get _isMutating => _isImporting || _deletingFontId != null;
  bool get canMutate =>
      !_disposed && !_isLoading && !_isMutating && !_isConfirming;
  bool get canSelect =>
      !_disposed && !_isLoading && !_isMutating && !_isConfirming;
  bool get canConfirm => canSelect && !_isResolving && _hasResolvedSelection;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    if (await reload() && !_disposed && _selectionGeneration == 0) {
      await selectFont(_initialFontId ?? FontIdentity.system);
    }
  }

  Future<void> retry() async {
    if (!canMutate) return;
    if (await reload() && !_disposed && _selectionGeneration == 0) {
      // A failed first catalog read never established the requested draft.
      await selectFont(_initialFontId ?? FontIdentity.system);
    }
  }

  Future<bool> reload() async {
    if (_disposed) return false;
    final generation = ++_catalogGeneration;
    _isLoading = true;
    _notify();
    try {
      final fonts = await _listFonts();
      if (_disposed || generation != _catalogGeneration) return false;
      _fonts = List.unmodifiable(fonts);
      _failure = null;
      if (_requestedFontId != FontIdentity.system &&
          !_fonts.any((font) => font.id == _requestedFontId)) {
        _selectionGeneration++;
        _requestedFontId = FontIdentity.system;
        _selectedFont = ResolvedFont.system;
        _isResolving = false;
        _hasResolvedSelection = true;
        _failure = FontLibraryFailure.notFound;
      }
      return true;
    } catch (error) {
      if (!_disposed && generation == _catalogGeneration) {
        _failure = _failureCode(error);
      }
      // Keep the last usable list and resolved selection on a transient read.
      return false;
    } finally {
      if (!_disposed && generation == _catalogGeneration) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> selectFont(String id) async {
    if (!canSelect) return;
    final generation = ++_selectionGeneration;
    _requestedFontId = id;
    _isResolving = true;
    _hasResolvedSelection = false;
    _failure = null;
    _notify();
    try {
      final resolution = await _resolveFont(id);
      if (_disposed || generation != _selectionGeneration) return;
      _selectedFont = resolution.font;
      _requestedFontId = resolution.font.id;
      _failure = resolution.failure;
      _hasResolvedSelection = true;
    } catch (error) {
      if (_disposed || generation != _selectionGeneration) return;
      _selectedFont = ResolvedFont.system;
      _requestedFontId = FontIdentity.system;
      _failure = _failureCode(error);
      _hasResolvedSelection = true;
    } finally {
      if (!_disposed && generation == _selectionGeneration) {
        _isResolving = false;
        _notify();
      }
    }
  }

  Future<void> importFont() async {
    if (!canMutate) return;
    final generation = ++_mutationGeneration;
    final selectionGeneration = _selectionGeneration;
    _isImporting = true;
    _failure = null;
    _notify();
    String? importedId;
    try {
      final file = await _pickFont();
      if (!_mutationIsCurrent(generation) || file == null) return;
      final imported = await _importFont(
        fileName: file.fileName,
        bytes: file.bytes,
      );
      if (!_mutationIsCurrent(generation)) return;
      _reloadPending = false;
      if (await reload()) importedId = imported.id;
    } catch (error) {
      if (_mutationIsCurrent(generation)) _failure = _failureCode(error);
    } finally {
      if (_mutationIsCurrent(generation)) {
        _isImporting = false;
        _notify();
        if (importedId != null && selectionGeneration == _selectionGeneration) {
          await selectFont(importedId);
        }
        _reloadIfPending();
      }
    }
  }

  Future<void> deleteFont(String id) async {
    if (!canMutate || id == FontIdentity.system) return;
    final generation = ++_mutationGeneration;
    _deletingFontId = id;
    _failure = null;
    _notify();
    try {
      await _deleteFont(id);
      if (!_mutationIsCurrent(generation)) return;
      if (_requestedFontId == id) {
        _selectionGeneration++;
        _requestedFontId = FontIdentity.system;
        _selectedFont = ResolvedFont.system;
        _isResolving = false;
        _hasResolvedSelection = true;
      } else if (_selectedFont.id == id) {
        _selectedFont = ResolvedFont.system;
      }
      _reloadPending = false;
      await reload();
    } catch (error) {
      if (_mutationIsCurrent(generation)) _failure = _failureCode(error);
    } finally {
      if (_mutationIsCurrent(generation)) {
        _deletingFontId = null;
        _notify();
        _reloadIfPending();
      }
    }
  }

  Future<ResolvedFont?> confirmSelection() async {
    if (!canConfirm) return null;
    _isConfirming = true;
    final generation = _selectionGeneration;
    _notify();
    try {
      // Another selector may have removed this font after the preview loaded.
      final resolution = await _resolveFont(_selectedFont.id);
      if (_disposed || generation != _selectionGeneration) return null;
      _selectedFont = resolution.font;
      _requestedFontId = resolution.font.id;
      _failure = resolution.failure;
      return resolution.failure == null ? resolution.font : null;
    } catch (error) {
      if (!_disposed && generation == _selectionGeneration) {
        _failure = _failureCode(error);
      }
      return null;
    } finally {
      if (!_disposed) {
        _isConfirming = false;
        _notify();
      }
    }
  }

  bool _mutationIsCurrent(int generation) =>
      !_disposed && generation == _mutationGeneration;

  void _reloadIfPending() {
    if (_reloadPending && !_disposed) {
      _reloadPending = false;
      unawaited(reload());
    }
  }

  FontLibraryFailure _failureCode(Object error) =>
      error is FontLibraryException ? error.code : FontLibraryFailure.storage;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _catalogGeneration++;
    _selectionGeneration++;
    _mutationGeneration++;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
