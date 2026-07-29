import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projector.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

/// Owns the display-only conversion generation for one reader comment session.
///
/// It observes raw comment results but never starts or retries a network load.
final class ComicCommentContentProjectionController extends ChangeNotifier {
  ComicCommentContentProjectionController({
    required ComicCommentSessionController session,
    required ComicCommentContentProjector projector,
    required TextConversionMode initialMode,
    required TextConverter initialConverter,
  }) : _session = session,
       _projector = projector,
       _mode = initialMode,
       _converter = initialConverter {
    _session.addListener(_onSessionChanged);
    _synchronize();
  }

  final ComicCommentSessionController _session;
  final ComicCommentContentProjector _projector;

  TextConversionMode _mode;
  TextConverter _converter;
  ComicCommentContentProjection? _projection;
  bool _isConverting = false;
  int _generation = 0;
  bool _disposed = false;

  ComicCommentContentProjection? get projection => _projection;
  bool get isConverting => _isConverting;

  void updateConversion({
    required TextConversionMode mode,
    required TextConverter converter,
  }) {
    if (_disposed || (_mode == mode && _converter.id == converter.id)) {
      return;
    }
    _mode = mode;
    _converter = converter;
    _synchronize(force: true);
  }

  ComicCommentContentProjection projectionFor(ComicCommentLoadResult source) {
    final revision = ComicCommentContentProjector.sourceRevisionFor(
      sessionKey: _session.key,
      source: source,
    );
    final candidate = _projection;
    if (candidate != null &&
        candidate.sourceRevision == revision &&
        candidate.mode == _mode &&
        candidate.converterId == _converter.id) {
      return candidate;
    }
    return ComicCommentContentProjection.raw(
      source,
      mode: _mode,
      converterId: _converter.id,
      sourceRevision: revision,
    );
  }

  void _onSessionChanged() => _synchronize();

  void _synchronize({bool force = false}) {
    if (_disposed) {
      return;
    }
    final source = _session.state.result;
    if (source == null) {
      final changed = _projection != null || _isConverting;
      _generation += 1;
      _projection = null;
      _isConverting = false;
      if (changed) {
        notifyListeners();
      }
      return;
    }

    final revision = ComicCommentContentProjector.sourceRevisionFor(
      sessionKey: _session.key,
      source: source,
    );
    final current = _projection;
    if (!force &&
        current != null &&
        current.sourceRevision == revision &&
        current.mode == _mode &&
        current.converterId == _converter.id) {
      return;
    }

    final generation = ++_generation;
    _projection = ComicCommentContentProjection.raw(
      source,
      mode: _mode,
      converterId: _converter.id,
      sourceRevision: revision,
    );
    _isConverting = _mode != TextConversionMode.none && source.items.isNotEmpty;
    notifyListeners();
    if (!_isConverting) {
      return;
    }

    unawaited(
      _project(
        generation: generation,
        source: source,
        converter: _converter,
        expectedRevision: revision,
      ),
    );
  }

  Future<void> _project({
    required int generation,
    required ComicCommentLoadResult source,
    required TextConverter converter,
    required String expectedRevision,
  }) async {
    final result = await _projector.project(
      sessionKey: _session.key,
      source: source,
      converter: converter,
    );
    if (_disposed ||
        generation != _generation ||
        _mode != converter.mode ||
        _converter.id != converter.id ||
        result.sourceRevision != expectedRevision) {
      return;
    }
    _projection = result;
    _isConverting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation += 1;
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }
}
