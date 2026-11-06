import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;

import '../../domain/models/novel_reader_preferences.dart';
import '../../domain/repositories/novel_reader_preferences_repository.dart';
import 'novel_reader_color_snapshot_codec.dart';
import 'novel_reader_preferences_snapshot_codec.dart';
import 'novel_reader_typography_snapshot_codec.dart';
import 'novel_reader_viewport_snapshot_codec.dart';

/// Only these complete requests can be overridden. For example, a spacing
/// value and its author policy are one request, but four margins are separate.
final class NovelReaderWorkPreferencesCodec {
  const NovelReaderWorkPreferencesCodec(this._snapshot);

  final NovelReaderPreferencesSnapshotCodec _snapshot;
  static const _version = 1;
  static const _namespaces = {
    'typography': NovelReaderTypographySnapshotCodec.schemaVersion,
    'viewport': NovelReaderViewportSnapshotCodec.schemaVersion,
    'colors': NovelReaderColorSnapshotCodec.schemaVersion,
  };
  static final _paths = {
    for (final field in [
      'fontSize',
      'lineHeight',
      'fontFamily',
      'flowMode',
      'themePreset',
      'conversionMode',
      'safeAreaEnabled',
      'compressBlankLines',
      'removeSourceIndent',
      'avoidIsolatedLines',
      'keepHeadingWithNext',
      'showRubyAnnotations',
      'typography.firstLineIndent',
      'typography.paragraphSpacing',
      'typography.letterSpacing',
      'typography.wordSpacing',
      'typography.fontWeight',
      'typography.textAlignment',
      'typography.fontSizePolicy',
      'typography.lineHeightPolicy',
      'typography.roleFontSizes.heading',
      'typography.roleFontSizes.quote',
      'typography.roleFontSizes.code',
      'typography.roleFontSizes.ruby',
      for (final edge in NovelReaderViewportEdge.values)
        'viewport.${edge.name}',
      'viewport.contentWidth',
      'colors.foreground',
      'colors.background',
      'colors.foregroundScope',
      'colors.backgroundScope',
    ])
      field: field.split('.'),
  };

  NovelReaderWorkPreferenceRecord decode(String? source) {
    if (source == null) return const NovelReaderWorkPreferenceRecord.empty();
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return const NovelReaderWorkPreferenceRecord.unsupported();
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != _version ||
        decoded['fields'] is! Map<String, dynamic>) {
      return const NovelReaderWorkPreferenceRecord.unsupported();
    }
    final fields = decoded['fields'] as Map<String, dynamic>;
    final known = {
      for (final entry in fields.entries)
        if (_paths.containsKey(entry.key)) entry.key: entry.value,
    };
    // Reuse the existing value validators. A future variant of a known
    // request stays read-only instead of being replaced by today's fallback.
    final canonical = known.isEmpty
        ? const <String, Object?>{}
        : _fields(apply(NovelReaderPreferences.defaults(), known));
    final valid = {
      for (final entry in known.entries)
        if (_sameField(canonical[entry.key], entry.value))
          entry.key: entry.value,
    };
    return NovelReaderWorkPreferenceRecord._(
      activeFields: valid,
      unknownFields: {
        for (final entry in fields.entries)
          if (!_paths.containsKey(entry.key)) entry.key: entry.value,
      },
      extensions: {
        for (final entry in decoded.entries)
          if (entry.key != 'schemaVersion' && entry.key != 'fields')
            entry.key: entry.value,
      },
      canEdit: valid.length == known.length,
    );
  }

  String? encode(
    NovelReaderWorkPreferenceRecord record,
    Map<String, Object?> changes, {
    bool reset = false,
  }) {
    if (!record.canEdit) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
    final fields = {
      ...record._unknownFields,
      if (!reset) ...record._activeFields,
      ...changes,
    };
    if (fields.isEmpty && record._extensions.isEmpty) return null;
    return jsonEncode({
      ...record._extensions,
      'schemaVersion': _version,
      'fields': fields,
    });
  }

  Map<String, Object?> changes(
    NovelReaderPreferences previous,
    NovelReaderPreferences next,
  ) {
    final before = _fields(previous);
    return {
      for (final entry in _fields(next).entries)
        if (!_sameField(before[entry.key], entry.value)) entry.key: entry.value,
    };
  }

  Map<String, Object?> presetFields(
    NovelReaderPreferences value, {
    required bool keepCurrentFont,
  }) {
    final fields = _fields(value);
    if (keepCurrentFont) fields.remove('fontFamily');
    return fields;
  }

  NovelReaderPreferences apply(
    NovelReaderPreferences defaults,
    Map<String, Object?> fields,
  ) {
    if (fields.isEmpty) return defaults;
    final payload = _payload(defaults);
    for (final entry in fields.entries) {
      final path = _paths[entry.key]!;
      var target = payload;
      for (final name in path.take(path.length - 1)) {
        target = target.putIfAbsent(
          name,
          () => <String, Object?>{'schemaVersion': ?_namespaces[name]},
        ) as Map<String, Object?>;
      }
      // A null clears the inherited optional request. An absent field leaves
      // the inherited request alone.
      if (entry.value == null) {
        target.remove(path.last);
      } else {
        target[path.last] = entry.value;
      }
    }
    return _snapshot.decode(jsonEncode(payload));
  }

  NovelReaderPreferenceScopes scope(
    NovelReaderPreferences defaults,
    NovelReaderWorkPreferenceRecord work,
  ) => _ResolvedScopes(defaults, work, this);

  Map<String, Object?> _fields(NovelReaderPreferences value) {
    final payload = _payload(value);
    return {
      for (final entry in _paths.entries)
        entry.key: _read(payload, entry.value),
      // The global codec omits these defaults, but a work may explicitly
      // select either boolean even when its global value differs.
      'compressBlankLines': value.compressBlankLines,
      'removeSourceIndent': value.removeSourceIndent,
      'avoidIsolatedLines': value.avoidIsolatedLines,
      'keepHeadingWithNext': value.keepHeadingWithNext,
      'showRubyAnnotations': value.showRubyAnnotations,
    };
  }

  Map<String, Object?> _payload(NovelReaderPreferences value) =>
      jsonDecode(_snapshot.encode(value)) as Map<String, Object?>;

  static Object? _read(Map<String, Object?> payload, List<String> path) {
    Object? node = payload;
    for (final name in path) {
      if (node is! Map<String, Object?>) return null;
      node = node[name];
    }
    return node;
  }

  // Canonical requests are either scalars or one map of scalar values.
  static bool _sameField(Object? left, Object? right) =>
      left is Map<String, Object?> && right is Map<String, Object?>
      ? mapEquals(left, right)
      : left == right;
}

final class NovelReaderWorkPreferenceRecord {
  const NovelReaderWorkPreferenceRecord.empty()
    : this._(activeFields: const {}, canEdit: true);
  const NovelReaderWorkPreferenceRecord.unsupported()
    : this._(activeFields: const {}, canEdit: false);
  const NovelReaderWorkPreferenceRecord._({
    required Map<String, Object?> activeFields,
    Map<String, Object?> unknownFields = const {},
    Map<String, Object?> extensions = const {},
    required this.canEdit,
  }) : _activeFields = activeFields,
       _unknownFields = unknownFields,
       _extensions = extensions;

  final Map<String, Object?> _activeFields;
  final Map<String, Object?> _unknownFields;
  final Map<String, Object?> _extensions;
  final bool canEdit;
}

final class _ResolvedScopes implements NovelReaderPreferenceScopes {
  _ResolvedScopes(this.defaults, this._work, this._codec);

  @override
  final NovelReaderPreferences defaults;
  final NovelReaderWorkPreferenceRecord _work;
  final NovelReaderWorkPreferencesCodec _codec;

  @override
  late final NovelReaderPreferences effective = previewDefaults(defaults);
  @override
  bool get hasWorkOverrides => _work._activeFields.isNotEmpty;
  @override
  bool get canEditWork => _work.canEdit;
  @override
  NovelReaderPreferenceScope get fontFamilyScope => _scopeOf('fontFamily');
  @override
  NovelReaderPreferenceScope get flowModeScope => _scopeOf('flowMode');

  NovelReaderPreferenceScope _scopeOf(String field) =>
      _work._activeFields.containsKey(field)
      ? NovelReaderPreferenceScope.work
      : NovelReaderPreferenceScope.defaults;

  @override
  NovelReaderPreferences previewDefaults(NovelReaderPreferences draft) =>
      _codec.apply(draft, _work._activeFields);

  @override
  NovelReaderPreferences previewEdit(
    NovelReaderPreferenceScope scope,
    NovelReaderPreferences previous,
    NovelReaderPreferences draft,
  ) {
    final changes = _codec.changes(previous, draft);
    return scope == NovelReaderPreferenceScope.defaults
        ? previewDefaults(_codec.apply(defaults, changes))
        : _codec.apply(effective, changes);
  }
}
