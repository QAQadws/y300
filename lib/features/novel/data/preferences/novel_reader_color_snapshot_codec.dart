import '../../domain/models/novel_reader_color_overrides.dart';
import '../../domain/repositories/novel_reader_preferences_repository.dart';
import 'novel_reader_style_scope_snapshot_codec.dart';

/// Optional namespace; future spaces/versions are read-only to this writer.
final class NovelReaderColorSnapshotCodec {
  const NovelReaderColorSnapshotCodec();
  static const schemaVersion = 1;
  static const _policy = NovelReaderStyleScopeSnapshotCodec();
  static const _metadata = {'space', 'value', 'enabled'};
  NovelReaderColorOverrides normalize(NovelReaderColorOverrides value) {
    int? rgb(int? v) =>
        v != null && NovelReaderColorOverrides.validRgb(v) ? v : null;
    return NovelReaderColorOverrides(
      foreground: rgb(value.foreground),
      background: rgb(value.background),
      foregroundScope: value.foregroundScope,
      backgroundScope: value.backgroundScope,
    );
  }

  bool _known(Object? input) =>
      input is Map<String, dynamic> &&
      input['space'] == 'srgb' &&
      (!input.containsKey('enabled') || input['enabled'] is bool);
  int? _decode(Object? input) {
    if (!_known(input)) return null;
    final raw = input as Map<String, dynamic>;
    if (raw['enabled'] == false) return null;
    final value = raw['value'];
    return value is int && NovelReaderColorOverrides.validRgb(value)
        ? value
        : null;
  }

  NovelReaderColorOverrides decode(Object? input) {
    if (input is! Map<String, dynamic> ||
        input['schemaVersion'] != schemaVersion) {
      return const NovelReaderColorOverrides();
    }
    return NovelReaderColorOverrides(
      foreground: _decode(input['foreground']),
      background: _decode(input['background']),
      foregroundScope: _policy.decode(input['foregroundScope']),
      backgroundScope: _policy.decode(input['backgroundScope']),
    );
  }

  Map<String, Object?>? _encode(Object? previous, int? value) {
    if (previous != null && !_known(previous)) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
    final prior = previous as Map<String, dynamic>?;
    if (value != null) {
      return {...?prior, 'space': 'srgb', 'value': value, 'enabled': true};
    }
    if (prior == null || prior.keys.every(_metadata.contains)) return null;
    return {...prior, 'enabled': false};
  }

  Map<String, Object?>? encode(
    NovelReaderColorOverrides input, {
    Object? previous,
  }) {
    if (previous != null &&
        (previous is! Map<String, dynamic> ||
            previous['schemaVersion'] != schemaVersion)) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
    final prior = previous as Map<String, dynamic>?;
    final normalized = normalize(input);
    final result = <String, Object?>{...?prior, 'schemaVersion': schemaVersion};
    for (final entry in {
      'foreground': _encode(prior?['foreground'], normalized.foreground),
      'background': _encode(prior?['background'], normalized.background),
      'foregroundScope': _policy.encode(
        normalized.foregroundScope,
        previous: prior?['foregroundScope'],
      ),
      'backgroundScope': _policy.encode(
        normalized.backgroundScope,
        previous: prior?['backgroundScope'],
      ),
    }.entries) {
      if (entry.value == null) {
        result.remove(entry.key);
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result.length == 1 ? null : result;
  }
}
