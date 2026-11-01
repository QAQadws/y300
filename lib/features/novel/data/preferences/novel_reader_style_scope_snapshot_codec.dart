import '../../domain/models/novel_reader_typography_overrides.dart';
import '../../domain/repositories/novel_reader_preferences_repository.dart';

/// A policy referencing an existing preference value, without duplicating its
/// number or unit in another snapshot field.
final class NovelReaderStyleScopeSnapshotCodec {
  const NovelReaderStyleScopeSnapshotCodec();
  static const _keys = {'scope', 'enabled'};

  static NovelReaderStyleScope? parseScope(Object? raw) => switch (raw) {
    'asDefault' => NovelReaderStyleScope.asDefault,
    'forceBody' => NovelReaderStyleScope.forceBody,
    'forceAll' => NovelReaderStyleScope.forceAll,
    _ => null,
  };

  bool _knownShape(Object? source) =>
      source is Map<String, dynamic> &&
      parseScope(source['scope']) != null &&
      (!source.containsKey('enabled') || source['enabled'] is bool);

  NovelReaderStyleScope? decode(Object? source) {
    if (!_knownShape(source)) return null;
    final raw = source as Map<String, dynamic>;
    return raw['enabled'] == false ? null : parseScope(raw['scope']);
  }

  Map<String, Object?>? encode(
    NovelReaderStyleScope? scope, {
    Object? previous,
  }) {
    if (previous != null && !_knownShape(previous)) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
    final prior = previous as Map<String, dynamic>?;
    if (scope != null) {
      return {...?prior, 'scope': scope.name, 'enabled': true};
    }
    if (prior == null || prior.keys.every(_keys.contains)) return null;
    // Retire only known behavior, retaining future extension data idempotently.
    return {...prior, 'enabled': false};
  }
}
