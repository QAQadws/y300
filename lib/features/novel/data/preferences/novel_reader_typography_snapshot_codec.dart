import '../../domain/models/novel_reader_typography_overrides.dart';
import '../../domain/repositories/novel_reader_preferences_repository.dart';
import 'novel_reader_style_scope_snapshot_codec.dart';
import 'novel_reader_text_alignment_snapshot_codec.dart';

/// Optional versioned namespace in the existing snapshot. New fields are
/// additive; older writers retain them as unknown extensions.
final class NovelReaderTypographySnapshotCodec {
  const NovelReaderTypographySnapshotCodec();
  static const schemaVersion = 1;
  static const _scopePolicy = NovelReaderStyleScopeSnapshotCodec();
  static const _alignment = NovelReaderTextAlignmentSnapshotCodec();
  static const _weight = _NumericRequestCodec(
    unit: 'cssWeight',
    minimum: 100,
    maximum: 800,
    step: 100,
    fields: ['value'],
  );
  static const _indent = _NumericRequestCodec(
    unit: 'em',
    maximum: NovelReaderFirstLineIndent.maximumEm,
    fields: ['value'],
  );
  static const _spacing = _NumericRequestCodec(
    unit: 'logicalPixels',
    maximum: NovelReaderParagraphSpacing.maximum,
    fields: ['before', 'after'],
  );
  static const _letters = _NumericRequestCodec(
    unit: 'logicalPixels',
    minimum: NovelReaderLetterSpacing.minimum,
    maximum: NovelReaderLetterSpacing.maximum,
    fields: ['value'],
  );
  static const _words = _NumericRequestCodec(
    unit: 'logicalPixels',
    minimum: NovelReaderWordSpacing.minimum,
    maximum: NovelReaderWordSpacing.maximum,
    fields: ['value'],
  );

  NovelReaderTypographyOverrides normalize(
    NovelReaderTypographyOverrides input,
  ) => NovelReaderTypographyOverrides(
    firstLineIndent: input.firstLineIndent?.isValid == true
        ? input.firstLineIndent
        : null,
    paragraphSpacing: input.paragraphSpacing?.isValid == true
        ? input.paragraphSpacing
        : null,
    letterSpacing: input.letterSpacing?.isValid == true
        ? input.letterSpacing
        : null,
    wordSpacing: input.wordSpacing?.isValid == true ? input.wordSpacing : null,
    fontSizeScope: input.fontSizeScope,
    lineHeightScope: input.lineHeightScope,
    fontWeight: input.fontWeight?.isValid == true ? input.fontWeight : null,
    textAlignment: input.textAlignment,
    roleFontSizes: NovelReaderRoleFontSizes(
      heading: NovelReaderRoleFontSizes.validPercent(
        input.roleFontSizes.heading,
      ),
      quote: NovelReaderRoleFontSizes.validPercent(input.roleFontSizes.quote),
      code: NovelReaderRoleFontSizes.validPercent(input.roleFontSizes.code),
    ),
  );

  NovelReaderTypographyOverrides decode(Object? source) {
    if (source is! Map<String, dynamic> ||
        source['schemaVersion'] != schemaVersion) {
      return const NovelReaderTypographyOverrides();
    }
    final indent = _indent.decode(source['firstLineIndent']);
    final spacing = _spacing.decode(source['paragraphSpacing']);
    final letters = _letters.decode(source['letterSpacing']);
    final words = _words.decode(source['wordSpacing']);
    final weight = _weight.decode(source['fontWeight']);
    final roleSizes = source['roleFontSizes'];
    return NovelReaderTypographyOverrides(
      roleFontSizes: roleSizes is Map<String, dynamic>
          ? NovelReaderRoleFontSizes(
              heading: NovelReaderRoleFontSizes.validPercent(
                roleSizes['heading'],
              ),
              quote: NovelReaderRoleFontSizes.validPercent(roleSizes['quote']),
              code: NovelReaderRoleFontSizes.validPercent(roleSizes['code']),
            )
          : const NovelReaderRoleFontSizes(),
      textAlignment: _alignment.decode(source['textAlignment']),
      fontWeight: weight == null
          ? null
          : NovelReaderFontWeight(
              value: weight.values['value']!.toInt(),
              scope: weight.scope,
            ),
      fontSizeScope: _scopePolicy.decode(source['fontSizePolicy']),
      lineHeightScope: _scopePolicy.decode(source['lineHeightPolicy']),
      wordSpacing: words == null
          ? null
          : NovelReaderWordSpacing(
              logicalPixels: words.values['value']!,
              scope: words.scope,
            ),
      firstLineIndent: indent == null
          ? null
          : NovelReaderFirstLineIndent(
              em: indent.values['value']!,
              scope: indent.scope,
            ),
      paragraphSpacing: spacing == null
          ? null
          : NovelReaderParagraphSpacing(
              before: spacing.values['before']!,
              after: spacing.values['after']!,
              scope: spacing.scope,
            ),
      letterSpacing: letters == null
          ? null
          : NovelReaderLetterSpacing(
              logicalPixels: letters.values['value']!,
              scope: letters.scope,
            ),
    );
  }

  Map<String, Object?>? encode(
    NovelReaderTypographyOverrides input, {
    Object? previous,
  }) {
    if (previous != null &&
        (previous is! Map<String, dynamic> ||
            previous['schemaVersion'] != schemaVersion)) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
    final prior = previous as Map<String, dynamic>?;
    final normalized = normalize(input);
    final indent = normalized.firstLineIndent;
    final spacing = normalized.paragraphSpacing;
    final letters = normalized.letterSpacing;
    final words = normalized.wordSpacing;
    final result = <String, Object?>{...?prior, 'schemaVersion': schemaVersion};
    final requests = {
      'roleFontSizes': _encodeRoleSizes(
        normalized.roleFontSizes,
        previous: prior?['roleFontSizes'],
      ),
      'textAlignment': _alignment.encode(
        normalized.textAlignment,
        previous: prior?['textAlignment'],
      ),
      'fontWeight': _weight.encode(
        prior?['fontWeight'],
        normalized.fontWeight == null
            ? null
            : (
                scope: normalized.fontWeight!.scope,
                values: {'value': normalized.fontWeight!.value.toDouble()},
              ),
      ),
      'lineHeightPolicy': _scopePolicy.encode(
        normalized.lineHeightScope,
        previous: prior?['lineHeightPolicy'],
      ),
      'fontSizePolicy': _scopePolicy.encode(
        normalized.fontSizeScope,
        previous: prior?['fontSizePolicy'],
      ),
      'wordSpacing': _words.encode(
        prior?['wordSpacing'],
        words == null
            ? null
            : (scope: words.scope, values: {'value': words.logicalPixels}),
      ),
      'letterSpacing': _letters.encode(
        prior?['letterSpacing'],
        letters == null
            ? null
            : (scope: letters.scope, values: {'value': letters.logicalPixels}),
      ),
      'firstLineIndent': _indent.encode(
        prior?['firstLineIndent'],
        indent == null
            ? null
            : (scope: indent.scope, values: {'value': indent.em}),
      ),
      'paragraphSpacing': _spacing.encode(
        prior?['paragraphSpacing'],
        spacing == null
            ? null
            : (
                scope: spacing.scope,
                values: {'before': spacing.before, 'after': spacing.after},
              ),
      ),
    };
    for (final entry in requests.entries) {
      if (entry.value == null) {
        result.remove(entry.key);
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result.length == 1 ? null : result;
  }

  Map<String, Object?>? _encodeRoleSizes(
    NovelReaderRoleFontSizes sizes, {
    required Object? previous,
  }) {
    if (previous != null && previous is! Map<String, dynamic>) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
    final result = <String, Object?>{...?previous as Map<String, dynamic>?};
    result.remove('heading');
    result.remove('quote');
    result.remove('code');
    if (sizes.heading != null) result['heading'] = sizes.heading;
    if (sizes.quote != null) result['quote'] = sizes.quote;
    if (sizes.code != null) result['code'] = sizes.code;
    return result.isEmpty ? null : result;
  }
}

typedef _NumericRequest = ({
  NovelReaderStyleScope scope,
  Map<String, double> values,
});

/// Shared compatibility mechanics for bounded numeric fields. Inactive known
/// values retain extensions and remain stable over unrelated saves and resets.
final class _NumericRequestCodec {
  const _NumericRequestCodec({
    required this.unit,
    required this.maximum,
    required this.fields,
    this.minimum = 0,
    this.step,
  });
  final String unit;
  final double maximum;
  final double minimum;
  final double? step;
  final List<String> fields;
  static const _metadata = {'unit', 'scope', 'enabled'};

  bool _knownShape(Object? source) =>
      source is Map<String, dynamic> &&
      source['unit'] == unit &&
      NovelReaderStyleScopeSnapshotCodec.parseScope(source['scope']) != null &&
      (!source.containsKey('enabled') || source['enabled'] is bool);

  _NumericRequest? decode(Object? source, {bool includeDisabled = false}) {
    if (!_knownShape(source)) return null;
    final raw = source as Map<String, dynamic>;
    if (!includeDisabled && raw['enabled'] == false) return null;
    final values = <String, double>{};
    for (final field in fields) {
      final value = raw[field];
      if (value is! num ||
          !value.isFinite ||
          value < minimum ||
          value > maximum ||
          (step != null && (value - minimum) % step! != 0)) {
        return null;
      }
      values[field] = value.toDouble();
    }
    return (
      scope: NovelReaderStyleScopeSnapshotCodec.parseScope(raw['scope'])!,
      values: values,
    );
  }

  Map<String, Object?>? encode(Object? previous, _NumericRequest? request) {
    if (previous != null && !_knownShape(previous)) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
    final prior = previous as Map<String, dynamic>?;
    if (request != null) {
      return {
        ...?prior,
        'unit': unit,
        ...request.values,
        'scope': request.scope.name,
        'enabled': true,
      };
    }
    if (prior == null ||
        prior.keys.every(
          (key) => _metadata.contains(key) || fields.contains(key),
        )) {
      return null;
    }
    // Retain extensions while disabling known behavior. Future semantic
    // changes must advance the namespace version, not reinterpret extensions.
    final old = decode(prior, includeDisabled: true);
    return {
      ...prior,
      'unit': unit,
      ...?old?.values,
      if (old == null)
        for (final field in fields) field: minimum,
      'scope':
          (old?.scope ??
                  NovelReaderStyleScopeSnapshotCodec.parseScope(
                    prior['scope'],
                  )!)
              .name,
      'enabled': false,
    };
  }
}
