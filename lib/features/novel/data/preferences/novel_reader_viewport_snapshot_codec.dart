import '../../domain/models/novel_reader_viewport_overrides.dart';
import '../../domain/repositories/novel_reader_preferences_repository.dart';

/// Versioned viewport requests; unknown formats must not be lost by old writers.
final class NovelReaderViewportSnapshotCodec {
  const NovelReaderViewportSnapshotCodec();
  static const schemaVersion = 1;
  static const _metadata = {'unit', 'value', 'enabled'};

  NovelReaderViewportOverrides normalize(NovelReaderViewportOverrides input) {
    double? margin(double? v) =>
        v != null && NovelReaderViewportOverrides.validMargin(v) ? v : null;
    return NovelReaderViewportOverrides(
      left: margin(input.left),
      top: margin(input.top),
      right: margin(input.right),
      bottom: margin(input.bottom),
      contentWidth: input.contentWidth?.isValid == true
          ? input.contentWidth
          : null,
    );
  }

  bool _knownNumber(Object? input) =>
      input is Map<String, dynamic> &&
      input['unit'] == 'logicalPixels' &&
      (!input.containsKey('enabled') || input['enabled'] is bool);
  bool _knownWidth(Object? input) =>
      _knownNumber(input) &&
      (input as Map<String, dynamic>)['mode'] is String &&
      NovelReaderContentWidthMode.values.any((m) => m.name == input['mode']);
  double? _number(
    Object? input, {
    double minimum = NovelReaderViewportOverrides.minimumMargin,
    double maximum = NovelReaderViewportOverrides.maximumMargin,
  }) {
    if (!_knownNumber(input)) return null;
    final raw = input as Map<String, dynamic>;
    if (raw['enabled'] == false) return null;
    final v = raw['value'];
    return v is num && v.isFinite && v >= minimum && v <= maximum
        ? v.toDouble()
        : null;
  }

  NovelReaderViewportOverrides decode(Object? input) {
    if (input is! Map<String, dynamic> ||
        input['schemaVersion'] != schemaVersion) {
      return const NovelReaderViewportOverrides();
    }
    final rawWidth = input['contentWidth'];
    final limit = _knownWidth(rawWidth)
        ? _number(
            rawWidth,
            minimum: NovelReaderContentWidth.minimum,
            maximum: NovelReaderContentWidth.maximum,
          )
        : null;
    return NovelReaderViewportOverrides(
      left: _number(input['left']),
      top: _number(input['top']),
      right: _number(input['right']),
      bottom: _number(input['bottom']),
      contentWidth: limit == null
          ? null
          : (rawWidth as Map<String, dynamic>)['mode'] == 'available'
          ? NovelReaderContentWidth.available(logicalPixels: limit)
          : NovelReaderContentWidth.limited(limit),
    );
  }

  Map<String, Object?>? _encodeNumber(
    Object? previous,
    double? value, {
    NovelReaderContentWidth? width,
    bool isWidth = false,
  }) {
    if (previous != null &&
        !(isWidth ? _knownWidth(previous) : _knownNumber(previous))) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
    final prior = previous as Map<String, dynamic>?;
    if (value != null) {
      return {
        ...?prior,
        'unit': 'logicalPixels',
        'value': value,
        if (isWidth) 'mode': width!.mode.name,
        'enabled': true,
      };
    }
    final keys = {..._metadata, if (isWidth) 'mode'};
    if (prior == null || prior.keys.every(keys.contains)) return null;
    return {...prior, 'enabled': false};
  }

  Map<String, Object?>? encode(
    NovelReaderViewportOverrides input, {
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
    final requests = <String, Map<String, Object?>?>{
      for (final edge in NovelReaderViewportEdge.values)
        edge.name: _encodeNumber(prior?[edge.name], normalized.marginFor(edge)),
      'contentWidth': _encodeNumber(
        prior?['contentWidth'],
        normalized.contentWidth?.logicalPixels,
        isWidth: true,
        width: normalized.contentWidth,
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
}
