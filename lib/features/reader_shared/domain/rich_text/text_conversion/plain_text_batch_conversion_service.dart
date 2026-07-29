import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

/// Converts a collection of independent plain-text values in one platform
/// call whenever it is safe to do so.
abstract interface class PlainTextBatchConversionService {
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  });
}

/// Runtime metrics emitted by [DefaultPlainTextBatchConversionService].
///
/// The metrics intentionally contain counts and flags only. They are useful
/// to a presentation projector without exposing the text being converted.
final class PlainTextBatchConversionMetrics {
  const PlainTextBatchConversionMetrics({
    required this.sourceCount,
    required this.convertibleSourceCount,
    required this.elapsedMs,
    required this.cacheHit,
    required this.usedIndividualFallback,
    this.failureType,
  });

  final int sourceCount;
  final int convertibleSourceCount;
  final int elapsedMs;
  final bool cacheHit;
  final bool usedIndividualFallback;
  final String? failureType;
}

typedef PlainTextBatchConversionMetricsListener =
    void Function(PlainTextBatchConversionMetrics metrics);

/// Thrown only when the service cannot preserve the input/output cardinality.
/// Platform conversion exceptions are deliberately allowed to propagate as-is.
final class PlainTextBatchConversionException implements Exception {
  const PlainTextBatchConversionException({
    required this.expectedCount,
    required this.actualCount,
  });

  final int expectedCount;
  final int actualCount;

  @override
  String toString() =>
      'PlainTextBatchConversionException('
      'expected=$expectedCount, actual=$actualCount)';
}

/// Default in-memory implementation of [PlainTextBatchConversionService].
final class DefaultPlainTextBatchConversionService
    implements PlainTextBatchConversionService {
  DefaultPlainTextBatchConversionService({
    this.maxCacheEntries = 32,
    this.maxCacheCodeUnits = 512 * 1024,
    this.metricsListener,
  }) : _cache = LinkedHashMap<_PlainTextBatchCacheKey, _CachedBatch>();

  static const String delimiter = '\uE000\uE001y300-plain-text\uE001\uE000';

  final int maxCacheEntries;
  final int maxCacheCodeUnits;
  final PlainTextBatchConversionMetricsListener? metricsListener;
  final LinkedHashMap<_PlainTextBatchCacheKey, _CachedBatch> _cache;

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    final stopwatch = Stopwatch()..start();
    final input = List<String>.unmodifiable(sources);
    final convertibleValues = <String>[];
    final seen = <String>{};

    for (final source in input) {
      if (source.isNotEmpty &&
          containsConvertibleHan(source) &&
          seen.add(source)) {
        convertibleValues.add(source);
      }
    }

    if (input.isEmpty ||
        converter.mode == TextConversionMode.none ||
        convertibleValues.isEmpty) {
      _notify(
        PlainTextBatchConversionMetrics(
          sourceCount: input.length,
          convertibleSourceCount: convertibleValues.length,
          elapsedMs: stopwatch.elapsedMilliseconds,
          cacheHit: false,
          usedIndividualFallback: false,
        ),
      );
      return List<String>.from(input);
    }

    final key = _PlainTextBatchCacheKey(
      converterId: converter.id,
      sources: input,
    );
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      _notify(
        PlainTextBatchConversionMetrics(
          sourceCount: input.length,
          convertibleSourceCount: convertibleValues.length,
          elapsedMs: stopwatch.elapsedMilliseconds,
          cacheHit: true,
          usedIndividualFallback: cached.usedIndividualFallback,
        ),
      );
      return List<String>.from(cached.values);
    }

    var usedIndividualFallback = false;
    try {
      final convertedValues = <String>[];
      if (convertibleValues.any((value) => value.contains(delimiter))) {
        usedIndividualFallback = true;
        convertedValues.addAll(
          await Future.wait(convertibleValues.map(converter.convertHtml)),
        );
      } else {
        final convertedBatch = await converter.convertHtml(
          convertibleValues.join(delimiter),
        );
        final parts = convertedBatch.split(delimiter);
        if (parts.length == convertibleValues.length) {
          convertedValues.addAll(parts);
        } else {
          usedIndividualFallback = true;
          convertedValues.addAll(
            await Future.wait(convertibleValues.map(converter.convertHtml)),
          );
        }
      }

      if (convertedValues.length != convertibleValues.length) {
        throw PlainTextBatchConversionException(
          expectedCount: convertibleValues.length,
          actualCount: convertedValues.length,
        );
      }

      final convertedBySource = <String, String>{};
      for (var i = 0; i < convertibleValues.length; i += 1) {
        convertedBySource[convertibleValues[i]] = convertedValues[i];
      }

      final result = <String>[
        for (final source in input) convertedBySource[source] ?? source,
      ];
      if (result.length != input.length) {
        throw PlainTextBatchConversionException(
          expectedCount: input.length,
          actualCount: result.length,
        );
      }

      _putCache(
        key,
        _CachedBatch(
          values: result,
          usedIndividualFallback: usedIndividualFallback,
        ),
      );
      _notify(
        PlainTextBatchConversionMetrics(
          sourceCount: input.length,
          convertibleSourceCount: convertibleValues.length,
          elapsedMs: stopwatch.elapsedMilliseconds,
          cacheHit: false,
          usedIndividualFallback: usedIndividualFallback,
        ),
      );
      return result;
    } catch (error) {
      _notify(
        PlainTextBatchConversionMetrics(
          sourceCount: input.length,
          convertibleSourceCount: convertibleValues.length,
          elapsedMs: stopwatch.elapsedMilliseconds,
          cacheHit: false,
          usedIndividualFallback: usedIndividualFallback,
          failureType: error.runtimeType.toString(),
        ),
      );
      rethrow;
    }
  }

  void _putCache(_PlainTextBatchCacheKey key, _CachedBatch value) {
    if (maxCacheEntries <= 0 || maxCacheCodeUnits <= 0) {
      return;
    }
    final codeUnits = value.values.fold<int>(
      key.codeUnitCost,
      (total, value) => total + value.length,
    );
    if (codeUnits > maxCacheCodeUnits) {
      return;
    }

    _cache[key] = value.copyWith(codeUnitCost: codeUnits);
    while (_cache.length > maxCacheEntries ||
        _cachedCodeUnits > maxCacheCodeUnits) {
      _cache.remove(_cache.keys.first);
    }
  }

  int get _cachedCodeUnits =>
      _cache.values.fold<int>(0, (total, value) => total + value.codeUnitCost);

  void _notify(PlainTextBatchConversionMetrics metrics) {
    try {
      metricsListener?.call(metrics);
    } catch (_) {
      // Diagnostics must never change conversion semantics.
    }
  }
}

/// Returns whether [value] contains a Han code point that OpenCC can process.
bool containsConvertibleHan(String value) {
  for (final codePoint in value.runes) {
    if ((codePoint >= 0x3400 && codePoint <= 0x4DBF) ||
        (codePoint >= 0x4E00 && codePoint <= 0x9FFF) ||
        (codePoint >= 0xF900 && codePoint <= 0xFAFF) ||
        (codePoint >= 0x20000 && codePoint <= 0x2FA1F)) {
      return true;
    }
  }
  return false;
}

final class _PlainTextBatchCacheKey {
  _PlainTextBatchCacheKey({
    required this.converterId,
    required Iterable<String> sources,
  }) : sources = List<String>.unmodifiable(sources);

  final String converterId;
  final List<String> sources;

  int get codeUnitCost =>
      converterId.length +
      sources.fold<int>(0, (total, value) => total + value.length);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! _PlainTextBatchCacheKey ||
        converterId != other.converterId ||
        sources.length != other.sources.length) {
      return false;
    }
    for (var i = 0; i < sources.length; i += 1) {
      if (sources[i] != other.sources[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(converterId, Object.hashAll(sources));
}

final class _CachedBatch {
  const _CachedBatch({
    required this.values,
    required this.usedIndividualFallback,
    this.codeUnitCost = 0,
  });

  final List<String> values;
  final bool usedIndividualFallback;
  final int codeUnitCost;

  _CachedBatch copyWith({int? codeUnitCost}) {
    return _CachedBatch(
      values: List<String>.unmodifiable(values),
      usedIndividualFallback: usedIndividualFallback,
      codeUnitCost: codeUnitCost ?? this.codeUnitCost,
    );
  }
}

final plainTextBatchConversionServiceProvider =
    Provider<PlainTextBatchConversionService>(
      (ref) => DefaultPlainTextBatchConversionService(),
    );
