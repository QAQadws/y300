import '../../domain/models/novel_reader_typography_overrides.dart';
import '../../domain/repositories/novel_reader_preferences_repository.dart';

/// Optional versioned namespace inside the existing snapshot. Old writers keep
/// it as extension data; no extra store, eager migration or implicit setting.
final class NovelReaderTypographySnapshotCodec {
  const NovelReaderTypographySnapshotCodec();
  static const schemaVersion = 1;
  static const _indentKeys = {'unit', 'value', 'scope', 'enabled'};

  NovelReaderTypographyOverrides normalize(
    NovelReaderTypographyOverrides input,
  ) => input.firstLineIndent?.isValid == true
      ? input
      : const NovelReaderTypographyOverrides();

  NovelReaderTypographyOverrides decode(Object? source) {
    if (source is! Map<String, dynamic> ||
        source['schemaVersion'] != schemaVersion) {
      return const NovelReaderTypographyOverrides();
    }
    final value = source['firstLineIndent'];
    if (value is! Map<String, dynamic> ||
        value['unit'] != 'em' ||
        value['enabled'] == false ||
        (value.containsKey('enabled') && value['enabled'] is! bool)) {
      return const NovelReaderTypographyOverrides();
    }
    final scope = _scope(value['scope']);
    final amount = value['value'];
    if (scope == null || amount is! num) {
      return const NovelReaderTypographyOverrides();
    }
    return normalize(
      NovelReaderTypographyOverrides(
        firstLineIndent: NovelReaderFirstLineIndent(
          em: amount.toDouble(),
          scope: scope,
        ),
      ),
    );
  }

  Map<String, Object?>? encode(
    NovelReaderTypographyOverrides input, {
    Object? previous,
  }) {
    _requireEditable(previous);
    final prior = previous as Map<String, dynamic>?;
    final oldIndent = prior?['firstLineIndent'] as Map<String, dynamic>?;
    final request = normalize(input).firstLineIndent;
    final result = <String, Object?>{...?prior, 'schemaVersion': schemaVersion};
    if (request != null) {
      result['firstLineIndent'] = <String, Object?>{
        ...?oldIndent,
        'unit': 'em',
        'value': request.em,
        'scope': request.scope.name,
        'enabled': true,
      };
    } else if (oldIndent != null &&
        oldIndent.keys.any((key) => !_indentKeys.contains(key))) {
      // Reset known behavior while retaining unknown extension data. Disabled
      // values are inert in schema1; future semantic changes need a new schema.
      final amount = oldIndent['value'];
      final old = amount is num
          ? NovelReaderFirstLineIndent(
              em: amount.toDouble(),
              scope: _scope(oldIndent['scope'])!,
            )
          : null;
      result['firstLineIndent'] = <String, Object?>{
        ...oldIndent,
        'unit': 'em',
        'value': old?.isValid == true ? old!.em : 0,
        'scope': (old?.scope ?? NovelReaderStyleScope.asDefault).name,
        'enabled': false,
      };
    } else {
      result.remove('firstLineIndent');
    }
    return result.length == 1 ? null : result;
  }

  void _requireEditable(Object? source) {
    if (source == null) return;
    if (source is! Map<String, dynamic> ||
        source['schemaVersion'] != schemaVersion) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
    final indent = source['firstLineIndent'];
    if (indent != null &&
        (indent is! Map<String, dynamic> ||
            indent['unit'] != 'em' ||
            _scope(indent['scope']) == null ||
            (indent.containsKey('enabled') && indent['enabled'] is! bool))) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
  }

  NovelReaderStyleScope? _scope(Object? raw) => switch (raw) {
    'asDefault' => NovelReaderStyleScope.asDefault,
    'forceBody' => NovelReaderStyleScope.forceBody,
    'forceAll' => NovelReaderStyleScope.forceAll,
    _ => null,
  };
}
