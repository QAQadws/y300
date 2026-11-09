import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_attach_token_promoter.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_bbcode_codec.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_collapse_format_sanitizer.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_selection_adapter.dart';

/// Synchronizes one surface's Quill document with its BBCode source.
///
/// Owns document listeners and deferred normalization, but never the controller,
/// focus, widgets, or persistence. The surface supplies its frame scheduler.
final class ComposerQuillDocumentSyncCoordinator {
  ComposerQuillDocumentSyncCoordinator({
    required QuillController controller,
    required void Function(void Function()) scheduleAfterFrame,
    required void Function(String) onBbCodeChanged,
    String? bbCode,
  }) : _controller = controller,
       _scheduleAfterFrame = scheduleAfterFrame,
       _onBbCodeChanged = onBbCodeChanged,
       _document = controller.document,
       _bbCode = bbCode ?? _codec.encodeDocument(controller.document) {
    _controller.addListener(_handleDocumentChanged);
    _scheduleNormalization();
  }

  static const _codec = ComposerQuillBbCodeCodec();
  static const _selectionAdapter = ComposerQuillSelectionAdapter();
  static const _attachTokenPromoter = ComposerQuillAttachTokenPromoter();
  static const _collapseFormatSanitizer =
      ComposerQuillCollapseFormatSanitizer();

  final QuillController _controller;
  final void Function(void Function()) _scheduleAfterFrame;
  final void Function(String) _onBbCodeChanged;
  Document _document;
  String _bbCode;
  String? _ignoredExternalEncoding;
  Object? _attachTask;
  Object? _sanitizeTask;
  int _generation = 0;
  bool _applyingExternal = false;
  int? _promotingGeneration;
  int? _sanitizingGeneration;
  bool _closed = false;

  String get bbCode => _bbCode;
  int get documentGeneration => _generation;

  void applyExternalBbCode(
    String source, {
    required int messageRevision,
    ComposerTextMutation? mutation,
  }) {
    if (_closed || source == _bbCode) return;
    final document = _codec.decodeDocument(source);
    final selection = mutation != null && mutation.revision == messageRevision
        ? _selectionAdapter.toQuillSelection(
            source: source,
            document: document,
            selection: mutation.resultSelection,
          )
        : null;

    // Retire both queues before controller notifications can reenter us.
    _adoptDocument(document);
    _ignoredExternalEncoding = _codec.encodeDocument(document);
    _applyingExternal = true;
    try {
      _controller.document = document;
      _controller.updateSelection(
        selection ?? TextSelection.collapsed(offset: document.length - 1),
        ChangeSource.local,
      );
      _bbCode = source;
    } finally {
      _applyingExternal = false;
    }
    // Other controller listeners may have replaced the document during apply.
    // Reconcile the actual current document before releasing deferred work.
    _handleDocumentChanged();
  }

  void _handleDocumentChanged() {
    if (_closed || _applyingExternal) return;
    if (!identical(_document, _controller.document)) {
      // A caller-owned controller may replace its document directly, too.
      _adoptDocument(_controller.document);
      _ignoredExternalEncoding = null;
    }
    // Encoding can stay identical when pasted attach text replaces an embed.
    // Structural normalization must therefore precede the BBCode early return.
    _scheduleNormalization();
    final next = _codec.encodeDocument(_document);
    if (_ignoredExternalEncoding != null) {
      if (next == _ignoredExternalEncoding) return;
      _ignoredExternalEncoding = null;
    }
    if (next == _bbCode) return;
    _bbCode = next;
    _onBbCodeChanged(next);
  }

  void _adoptDocument(Document document) {
    _document = document;
    _generation += 1;
    _attachTask = null;
    _sanitizeTask = null;
  }

  bool _isCurrent(Document document, int generation) =>
      !_closed &&
      generation == _generation &&
      identical(document, _document) &&
      identical(document, _controller.document);

  void _scheduleNormalization() {
    if (_promotingGeneration != _generation) _scheduleAttachPromotion();
    if (_sanitizingGeneration != _generation) _scheduleCollapseSanitization();
  }

  void _scheduleAttachPromotion() {
    if (_attachTask != null) return;
    final task = _attachTask = Object();
    final document = _document;
    final generation = _generation;
    // Keep this after the frame: Quill notifications and IME input must finish
    // before literal attachment codes are composed into atomic embeds.
    _scheduleAfterFrame(() {
      if (!identical(_attachTask, task)) return;
      _attachTask = null;
      if (!_isCurrent(document, generation)) return;
      final promotion = _attachTokenPromoter.buildPromotion(document);
      if (promotion == null) return;
      _promotingGeneration = generation;
      try {
        // compose transforms the live selection through the replacement delta.
        _controller.compose(
          promotion,
          _controller.selection,
          ChangeSource.local,
        );
      } finally {
        _promotingGeneration = null;
      }
    });
  }

  void _scheduleCollapseSanitization() {
    if (_sanitizeTask != null) return;
    final task = _sanitizeTask = Object();
    final document = _document;
    final generation = _generation;
    scheduleMicrotask(() {
      // An old callback must not clear the new document's pending work.
      if (!identical(_sanitizeTask, task)) return;
      _sanitizeTask = null;
      if (!_isCurrent(document, generation)) return;
      final sanitization = _collapseFormatSanitizer.buildSanitization(document);
      if (sanitization == null) return;
      _sanitizingGeneration = generation;
      try {
        _controller.compose(
          sanitization,
          _controller.selection,
          ChangeSource.local,
        );
      } finally {
        _sanitizingGeneration = null;
      }
    });
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _attachTask = null;
    _sanitizeTask = null;
    _controller.removeListener(_handleDocumentChanged);
  }
}
