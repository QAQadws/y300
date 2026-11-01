import '../../domain/models/novel_reader_typography_overrides.dart';
import '../../domain/repositories/novel_reader_preferences_repository.dart';
import 'novel_reader_style_scope_snapshot_codec.dart';

/// An enum request stays distinct from absence and preserves unknown formats.
final class NovelReaderTextAlignmentSnapshotCodec {
  const NovelReaderTextAlignmentSnapshotCodec();
  static const _keys = {'value', 'scope', 'enabled'};

  NovelReaderTextAlignMode? _mode(Object? value) => switch (value) {
    'start' => NovelReaderTextAlignMode.start,
    'end' => NovelReaderTextAlignMode.end,
    'justify' => NovelReaderTextAlignMode.justify,
    'center' => NovelReaderTextAlignMode.center,
    _ => null,
  };
  bool _knownShape(Object? source) =>
      source is Map<String, dynamic> &&
      _mode(source['value']) != null &&
      NovelReaderStyleScopeSnapshotCodec.parseScope(source['scope']) != null &&
      (!source.containsKey('enabled') || source['enabled'] is bool);

  NovelReaderTextAlignment? decode(Object? source) {
    if (!_knownShape(source)) return null;
    final raw = source as Map<String, dynamic>;
    return raw['enabled'] == false
        ? null
        : NovelReaderTextAlignment(
            mode: _mode(raw['value'])!,
            scope: NovelReaderStyleScopeSnapshotCodec.parseScope(raw['scope'])!,
          );
  }

  Map<String, Object?>? encode(
    NovelReaderTextAlignment? request, {
    Object? previous,
  }) {
    if (previous != null && !_knownShape(previous)) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
    final prior = previous as Map<String, dynamic>?;
    if (request != null) {
      return {
        ...?prior,
        'value': request.mode.name,
        'scope': request.scope.name,
        'enabled': true,
      };
    }
    if (prior == null || prior.keys.every(_keys.contains)) return null;
    return {...prior, 'enabled': false};
  }
}
