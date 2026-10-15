import 'dart:collection';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_exclusion_policy.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

/// Converts displayable HTML text nodes while preserving the document shape.
abstract class HtmlTextNodeConversionService {
  const HtmlTextNodeConversionService();

  Future<List<HtmlTextNodeConversionResult>> convertAll({
    required List<String> htmlFragments,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
  });

  /// Compatibility entry point for existing single-fragment callers.
  Future<HtmlTextNodeConversionResult> convert({
    required String html,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
  }) async {
    final results = await convertAll(
      htmlFragments: [html],
      converter: converter,
      options: options,
    );
    if (results.length != 1) {
      throw HtmlTextNodeConversionException(
        expectedCount: 1,
        actualCount: results.length,
      );
    }
    return results.first;
  }
}

/// Optional operation-scoped instrumentation contract for presentation
/// projectors.
///
/// Keeping this additive avoids forcing lightweight test doubles to implement
/// diagnostics they do not need.
abstract interface class ObservableHtmlTextNodeConversionService
    implements HtmlTextNodeConversionService {
  Future<List<HtmlTextNodeConversionResult>> convertAllObserved({
    required List<String> htmlFragments,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
    required HtmlTextNodeConversionMetricsListener metricsListener,
  });
}

final class DomHtmlTextNodeConversionService
    extends HtmlTextNodeConversionService
    implements ObservableHtmlTextNodeConversionService {
  DomHtmlTextNodeConversionService({
    PlainTextBatchConversionService? plainTextBatchConversionService,
    int maxCacheEntries = 8,
    int maxCacheCodeUnits = 8 * 1024 * 1024,
    this.metricsListener,
  }) : _plainTextBatchConversionService =
           plainTextBatchConversionService ??
           DefaultPlainTextBatchConversionService(),
       _maxCacheEntries = maxCacheEntries,
       _maxCacheCodeUnits = maxCacheCodeUnits,
       _cache = LinkedHashMap();

  final PlainTextBatchConversionService _plainTextBatchConversionService;
  final int _maxCacheEntries;
  final int _maxCacheCodeUnits;
  final HtmlTextNodeConversionMetricsListener? metricsListener;
  final LinkedHashMap<_HtmlTextNodeConversionCacheKey, _CachedHtmlBatch> _cache;

  @override
  Future<List<HtmlTextNodeConversionResult>> convertAll({
    required List<String> htmlFragments,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
  }) {
    return _convertAll(
      htmlFragments: htmlFragments,
      converter: converter,
      options: options,
    );
  }

  @override
  Future<List<HtmlTextNodeConversionResult>> convertAllObserved({
    required List<String> htmlFragments,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
    required HtmlTextNodeConversionMetricsListener metricsListener,
  }) {
    return _convertAll(
      htmlFragments: htmlFragments,
      converter: converter,
      options: options,
      operationMetricsListener: metricsListener,
    );
  }

  Future<List<HtmlTextNodeConversionResult>> _convertAll({
    required List<String> htmlFragments,
    required TextConverter converter,
    required HtmlTextNodeConversionOptions options,
    HtmlTextNodeConversionMetricsListener? operationMetricsListener,
  }) async {
    final stopwatch = Stopwatch()..start();
    final input = List<String>.unmodifiable(htmlFragments);
    if (input.isEmpty) {
      _notify(
        HtmlTextNodeConversionMetrics(
          htmlFragmentCount: 0,
          plainSourceCount: 0,
          convertedTextNodeCount: 0,
          elapsedMs: stopwatch.elapsedMilliseconds,
          cacheHit: false,
          usedIndividualFallback: false,
        ),
        operationMetricsListener: operationMetricsListener,
      );
      return const [];
    }

    if (converter.mode == TextConversionMode.none) {
      final result = _rawResults(input, converter.id);
      _notify(
        HtmlTextNodeConversionMetrics(
          htmlFragmentCount: input.length,
          plainSourceCount: 0,
          convertedTextNodeCount: 0,
          elapsedMs: stopwatch.elapsedMilliseconds,
          cacheHit: false,
          usedIndividualFallback: false,
        ),
        operationMetricsListener: operationMetricsListener,
      );
      return result;
    }

    final key = _HtmlTextNodeConversionCacheKey(
      htmlFragments: input,
      converterId: converter.id,
      optionsSignature: options.signature,
    );
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      _notify(
        HtmlTextNodeConversionMetrics(
          htmlFragmentCount: input.length,
          plainSourceCount: cached.plainSourceCount,
          convertedTextNodeCount: cached.convertedTextNodeCount,
          elapsedMs: stopwatch.elapsedMilliseconds,
          cacheHit: true,
          usedIndividualFallback: false,
          cachedHtmlFragmentCount: input.length,
        ),
        operationMetricsListener: operationMetricsListener,
      );
      return _copyResults(cached.results);
    }

    final work = _HtmlConversionWork();
    final allowFragmentReuse =
        converter is IndependentTextValueConverter &&
        _plainTextBatchConversionService
            is DefaultPlainTextBatchConversionService &&
        options.exclusionPolicies.every(
          // Injected policies may depend on visit order or mutable state. Only
          // the canonical structural policy is known to be fragment-local.
          (policy) =>
              identical(policy, const YamiboUserProfileLinkExclusionPolicy()),
        );
    try {
      final outcome = allowFragmentReuse
          ? await _convertIncremental(
              key: key,
              converter: converter,
              options: options,
              work: work,
            )
          : await _convertUncached(
              htmlFragments: input,
              converter: converter,
              options: options,
              work: work,
            );
      _putCache(key, outcome, allowFragmentReuse: allowFragmentReuse);
      _notify(
        HtmlTextNodeConversionMetrics(
          htmlFragmentCount: input.length,
          plainSourceCount: outcome.plainSourceCount,
          convertedTextNodeCount: outcome.convertedTextNodeCount,
          elapsedMs: stopwatch.elapsedMilliseconds,
          cacheHit: work.cachedHtmlFragmentCount == input.length,
          usedIndividualFallback: outcome.usedIndividualFallback,
          cachedHtmlFragmentCount: work.cachedHtmlFragmentCount,
          parsedHtmlFragmentCount: work.parsedHtmlFragmentCount,
          deduplicatedHtmlFragmentCount: work.deduplicatedHtmlFragmentCount,
          submittedPlainSourceCount: work.submittedPlainSourceCount,
        ),
        operationMetricsListener: operationMetricsListener,
      );
      return outcome.results;
    } catch (error) {
      _notify(
        HtmlTextNodeConversionMetrics(
          htmlFragmentCount: input.length,
          plainSourceCount: 0,
          convertedTextNodeCount: 0,
          elapsedMs: stopwatch.elapsedMilliseconds,
          cacheHit: false,
          usedIndividualFallback: false,
          cachedHtmlFragmentCount: work.cachedHtmlFragmentCount,
          parsedHtmlFragmentCount: work.parsedHtmlFragmentCount,
          deduplicatedHtmlFragmentCount: work.deduplicatedHtmlFragmentCount,
          submittedPlainSourceCount: work.submittedPlainSourceCount,
          failureType: error.runtimeType.toString(),
        ),
        operationMetricsListener: operationMetricsListener,
      );
      rethrow;
    }
  }

  Future<_HtmlTextNodeConversionOutcome> _convertIncremental({
    required _HtmlTextNodeConversionCacheKey key,
    required TextConverter converter,
    required HtmlTextNodeConversionOptions options,
    required _HtmlConversionWork work,
  }) async {
    // Reuse the bounded successful batch store, without a second retained cache.
    final requested = key.htmlFragments.toSet();
    final reusable =
        <String, ({HtmlTextNodeConversionResult result, int plainCount})>{};
    for (final entry in _cache.entries) {
      if (!entry.value.allowFragmentReuse ||
          entry.key.converterId != key.converterId ||
          entry.key.optionsSignature != key.optionsSignature) {
        continue;
      }
      for (var i = 0; i < entry.key.htmlFragments.length; i++) {
        final result = entry.value.results[i];
        // No-Han fragments are raw in an all-no-Han batch, but serialized in
        // a mixed batch. Keep their existing context-dependent output path.
        if (result.convertedTextNodeCount == 0 ||
            !requested.contains(entry.key.htmlFragments[i])) {
          continue;
        }
        reusable[entry.key.htmlFragments[i]] = (
          result: result,
          plainCount: entry.value.plainSourceCountsByFragment[i],
        );
      }
    }
    final results = List<HtmlTextNodeConversionResult?>.filled(
      key.htmlFragments.length,
      null,
    );
    final plainCounts = List<int>.filled(key.htmlFragments.length, 0);
    final pending = <String>[];
    final pendingIndex = <String, int>{};
    final positions = <List<int>>[];
    for (var index = 0; index < key.htmlFragments.length; index++) {
      final html = key.htmlFragments[index];
      final cached = reusable[html];
      if (cached != null) {
        results[index] = cached.result;
        plainCounts[index] = cached.plainCount;
        work.cachedHtmlFragmentCount++;
        continue;
      }
      final existing = pendingIndex[html];
      if (existing != null) {
        positions[existing].add(index);
        work.deduplicatedHtmlFragmentCount++;
      } else {
        pendingIndex[html] = pending.length;
        pending.add(html);
        positions.add(<int>[index]);
      }
    }
    var usedIndividualFallback = false;
    if (pending.isNotEmpty) {
      final fresh = await _convertUncached(
        htmlFragments: pending,
        converter: converter,
        options: options,
        work: work,
        forceSerialization: work.cachedHtmlFragmentCount > 0,
      );
      usedIndividualFallback = fresh.usedIndividualFallback;
      for (var index = 0; index < pending.length; index++) {
        for (final position in positions[index]) {
          results[position] = fresh.results[index];
          plainCounts[position] = fresh.plainSourceCountsByFragment[index];
        }
      }
    }
    final complete = <HtmlTextNodeConversionResult>[
      for (final result in results) result!,
    ];
    return _HtmlTextNodeConversionOutcome(
      results: complete,
      plainSourceCount: plainCounts.fold<int>(0, (sum, count) => sum + count),
      plainSourceCountsByFragment: plainCounts,
      convertedTextNodeCount: complete.fold<int>(
        0,
        (sum, result) => sum + result.convertedTextNodeCount,
      ),
      usedIndividualFallback: usedIndividualFallback,
    );
  }

  Future<_HtmlTextNodeConversionOutcome> _convertUncached({
    required List<String> htmlFragments,
    required TextConverter converter,
    required HtmlTextNodeConversionOptions options,
    required _HtmlConversionWork work,
    bool forceSerialization = false,
  }) async {
    final documents = <html_dom.DocumentFragment>[];
    for (final html in htmlFragments) {
      documents.add(html_parser.parseFragment(html));
      work.parsedHtmlFragmentCount++;
    }
    final textNodesByFragment = <List<html_dom.Text>>[];
    final sourceValues = <String>[];
    final convertedNodeCounts = <int>[];

    for (final fragment in documents) {
      final textNodes = <html_dom.Text>[];
      for (final node in fragment.nodes) {
        _collectConvertibleTextNodes(node, options, textNodes);
      }
      textNodesByFragment.add(textNodes);
      sourceValues.addAll([for (final node in textNodes) node.data]);
      convertedNodeCounts.add(
        textNodes.where((node) => containsConvertibleHan(node.data)).length,
      );
    }

    final plainCounts = <int>[
      for (final nodes in textNodesByFragment) nodes.length,
    ];
    if (sourceValues.isEmpty ||
        convertedNodeCounts.every((count) => count == 0)) {
      return _HtmlTextNodeConversionOutcome(
        results: forceSerialization
            ? <HtmlTextNodeConversionResult>[
                for (final document in documents)
                  HtmlTextNodeConversionResult(
                    html: _serializeFragment(document),
                    convertedTextNodeCount: 0,
                    converterId: converter.id,
                  ),
              ]
            : _rawResults(htmlFragments, converter.id),
        plainSourceCount: forceSerialization ? sourceValues.length : 0,
        plainSourceCountsByFragment: forceSerialization
            ? plainCounts
            : List<int>.filled(htmlFragments.length, 0),
        convertedTextNodeCount: 0,
        usedIndividualFallback: false,
      );
    }

    PlainTextBatchConversionMetrics? plainMetrics;
    work.submittedPlainSourceCount = sourceValues.length;
    final convertedValues =
        _plainTextBatchConversionService
            is ObservablePlainTextBatchConversionService
        ? await _plainTextBatchConversionService.convertAllObserved(
            sources: sourceValues,
            converter: converter,
            metricsListener: (value) => plainMetrics = value,
          )
        : await _plainTextBatchConversionService.convertAll(
            sources: sourceValues,
            converter: converter,
          );
    if (convertedValues.length != sourceValues.length) {
      throw HtmlTextNodeConversionException(
        expectedCount: sourceValues.length,
        actualCount: convertedValues.length,
      );
    }

    var valueIndex = 0;
    for (final textNodes in textNodesByFragment) {
      for (final textNode in textNodes) {
        textNode.data = convertedValues[valueIndex];
        valueIndex += 1;
      }
    }
    if (valueIndex != convertedValues.length) {
      throw HtmlTextNodeConversionException(
        expectedCount: convertedValues.length,
        actualCount: valueIndex,
      );
    }

    return _HtmlTextNodeConversionOutcome(
      results: [
        for (var i = 0; i < documents.length; i += 1)
          HtmlTextNodeConversionResult(
            html: _serializeFragment(documents[i]),
            convertedTextNodeCount: convertedNodeCounts[i],
            converterId: converter.id,
          ),
      ],
      plainSourceCount: sourceValues.length,
      plainSourceCountsByFragment: plainCounts,
      convertedTextNodeCount: convertedNodeCounts.fold<int>(
        0,
        (total, count) => total + count,
      ),
      usedIndividualFallback: plainMetrics?.usedIndividualFallback ?? false,
    );
  }

  void _collectConvertibleTextNodes(
    html_dom.Node node,
    HtmlTextNodeConversionOptions options,
    List<html_dom.Text> output,
  ) {
    if (node is html_dom.Text) {
      // Collection starts at fragment roots and never enters excluded subtrees.
      // Rechecking ancestors here would repeat policy work for every text node.
      if (node.data.trim().isNotEmpty) {
        output.add(node);
      }
      return;
    }

    if (node is html_dom.Element && _shouldSkipElement(node, options)) {
      return;
    }

    for (final child in node.nodes) {
      _collectConvertibleTextNodes(child, options, output);
    }
  }

  bool _shouldSkipElement(
    html_dom.Element element,
    HtmlTextNodeConversionOptions options,
  ) {
    final tagName = element.localName?.toLowerCase();
    if (tagName != null && options.skipTags.contains(tagName)) {
      return true;
    }
    if (element.classes.any(options.skipClassNames.contains)) {
      return true;
    }
    return options.exclusionPolicies.any((policy) => policy.excludes(element));
  }

  List<HtmlTextNodeConversionResult> _rawResults(
    Iterable<String> htmlFragments,
    String converterId,
  ) {
    return [
      for (final html in htmlFragments)
        HtmlTextNodeConversionResult(
          html: html,
          convertedTextNodeCount: 0,
          converterId: converterId,
        ),
    ];
  }

  String _serializeFragment(html_dom.DocumentFragment fragment) {
    return fragment.nodes.map(_serializeNode).join();
  }

  String _serializeNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      return node.outerHtml;
    }
    if (node is html_dom.Text) {
      return const HtmlEscape().convert(node.data);
    }
    return node.text ?? '';
  }

  void _putCache(
    _HtmlTextNodeConversionCacheKey key,
    _HtmlTextNodeConversionOutcome outcome, {
    required bool allowFragmentReuse,
  }) {
    if (_maxCacheEntries <= 0 || _maxCacheCodeUnits <= 0) {
      return;
    }
    final cachedBatch = _CachedHtmlBatch(
      results: _copyResults(outcome.results),
      plainSourceCount: outcome.plainSourceCount,
      convertedTextNodeCount: outcome.convertedTextNodeCount,
      codeUnitCost: _cacheCodeUnitCost(key, outcome),
      plainSourceCountsByFragment: List<int>.unmodifiable(
        outcome.plainSourceCountsByFragment,
      ),
      allowFragmentReuse: allowFragmentReuse,
    );
    if (cachedBatch.codeUnitCost > _maxCacheCodeUnits) {
      return;
    }
    _cache[key] = cachedBatch;
    while (_cache.length > _maxCacheEntries ||
        _cachedCodeUnits > _maxCacheCodeUnits) {
      _cache.remove(_cache.keys.first);
    }
  }

  int _cacheCodeUnitCost(
    _HtmlTextNodeConversionCacheKey key,
    _HtmlTextNodeConversionOutcome outcome,
  ) {
    final resultCodeUnits = outcome.results.fold<int>(
      0,
      (total, result) => total + result.html.length + result.converterId.length,
    );
    // Count a small fixed metadata budget for each result and batch counter.
    final metadataCodeUnits = 16 + (outcome.results.length * 12);
    return key.codeUnitCost + resultCodeUnits + metadataCodeUnits;
  }

  int get _cachedCodeUnits =>
      _cache.values.fold<int>(0, (total, value) => total + value.codeUnitCost);

  List<HtmlTextNodeConversionResult> _copyResults(
    Iterable<HtmlTextNodeConversionResult> results,
  ) {
    return [
      for (final result in results)
        HtmlTextNodeConversionResult(
          html: result.html,
          convertedTextNodeCount: result.convertedTextNodeCount,
          converterId: result.converterId,
        ),
    ];
  }

  void _notify(
    HtmlTextNodeConversionMetrics metrics, {
    HtmlTextNodeConversionMetricsListener? operationMetricsListener,
  }) {
    try {
      metricsListener?.call(metrics);
    } catch (_) {
      // Diagnostics must never change conversion semantics.
    }
    try {
      operationMetricsListener?.call(metrics);
    } catch (_) {
      // Operation diagnostics must not change conversion semantics either.
    }
  }
}

final htmlTextNodeConversionServiceProvider =
    Provider<HtmlTextNodeConversionService>((ref) {
      return DomHtmlTextNodeConversionService(
        plainTextBatchConversionService: ref.watch(
          plainTextBatchConversionServiceProvider,
        ),
      );
    });

final class HtmlTextNodeConversionOptions {
  const HtmlTextNodeConversionOptions({
    this.skipTags = const {'script', 'style', 'pre', 'code', 'textarea'},
    this.skipClassNames = const {'blockcode'},
    this.exclusionPolicies = const [YamiboUserProfileLinkExclusionPolicy()],
  });

  final Set<String> skipTags;
  final Set<String> skipClassNames;
  final List<HtmlTextNodeExclusionPolicy> exclusionPolicies;

  String get signature {
    // Match the actual skip checks, including tag spelling and unambiguous
    // policy IDs; comma-containing values must not alias separate entries.
    final tags = skipTags.toList()..sort();
    final classes = skipClassNames.toList()..sort();
    final policies = exclusionPolicies.map((policy) => policy.id).toList()
      ..sort();
    return jsonEncode(<Object>[tags, classes, policies]);
  }
}

final class HtmlTextNodeConversionResult {
  const HtmlTextNodeConversionResult({
    required this.html,
    required this.convertedTextNodeCount,
    required this.converterId,
  });

  final String html;
  final int convertedTextNodeCount;
  final String converterId;
}

final class HtmlTextNodeConversionMetrics {
  const HtmlTextNodeConversionMetrics({
    required this.htmlFragmentCount,
    required this.plainSourceCount,
    required this.convertedTextNodeCount,
    required this.elapsedMs,
    required this.cacheHit,
    required this.usedIndividualFallback,
    this.cachedHtmlFragmentCount = 0,
    this.parsedHtmlFragmentCount = 0,
    this.deduplicatedHtmlFragmentCount = 0,
    this.submittedPlainSourceCount = 0,
    this.failureType,
  });

  final int htmlFragmentCount;

  /// Logical totals for the complete ordered result, including cached repeats.
  final int plainSourceCount;
  final int convertedTextNodeCount;
  final int elapsedMs;

  /// True when every result came from a retained batch, including reordering.
  final bool cacheHit;
  final bool usedIndividualFallback;
  final String? failureType;
  final int cachedHtmlFragmentCount;
  final int parsedHtmlFragmentCount;
  final int deduplicatedHtmlFragmentCount;

  /// Text values handed to the plain batch service in this operation, before
  /// its own duplicate filtering or native conversion cache lookup.
  final int submittedPlainSourceCount;
}

typedef HtmlTextNodeConversionMetricsListener =
    void Function(HtmlTextNodeConversionMetrics metrics);

final class _HtmlTextNodeConversionOutcome {
  const _HtmlTextNodeConversionOutcome({
    required this.results,
    required this.plainSourceCount,
    required this.plainSourceCountsByFragment,
    required this.convertedTextNodeCount,
    required this.usedIndividualFallback,
  });

  final List<HtmlTextNodeConversionResult> results;
  final int plainSourceCount;
  final List<int> plainSourceCountsByFragment;
  final int convertedTextNodeCount;
  final bool usedIndividualFallback;
}

final class _CachedHtmlBatch {
  const _CachedHtmlBatch({
    required this.results,
    required this.plainSourceCount,
    required this.convertedTextNodeCount,
    required this.codeUnitCost,
    required this.plainSourceCountsByFragment,
    required this.allowFragmentReuse,
  });

  final List<HtmlTextNodeConversionResult> results;
  final int plainSourceCount;
  final int convertedTextNodeCount;
  final int codeUnitCost;
  final List<int> plainSourceCountsByFragment;
  final bool allowFragmentReuse;
}

final class _HtmlConversionWork {
  int cachedHtmlFragmentCount = 0;
  int parsedHtmlFragmentCount = 0;
  int deduplicatedHtmlFragmentCount = 0;
  int submittedPlainSourceCount = 0;
}

final class HtmlTextNodeConversionException implements Exception {
  const HtmlTextNodeConversionException({
    required this.expectedCount,
    required this.actualCount,
  });

  final int expectedCount;
  final int actualCount;

  @override
  String toString() =>
      'HtmlTextNodeConversionException('
      'expected=$expectedCount, actual=$actualCount)';
}

final class _HtmlTextNodeConversionCacheKey {
  _HtmlTextNodeConversionCacheKey({
    required Iterable<String> htmlFragments,
    required this.converterId,
    required this.optionsSignature,
  }) : htmlFragments = List<String>.unmodifiable(htmlFragments);

  final List<String> htmlFragments;
  final String converterId;
  final String optionsSignature;

  int get codeUnitCost =>
      converterId.length +
      optionsSignature.length +
      htmlFragments.fold<int>(0, (total, fragment) => total + fragment.length);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! _HtmlTextNodeConversionCacheKey ||
        converterId != other.converterId ||
        optionsSignature != other.optionsSignature ||
        htmlFragments.length != other.htmlFragments.length) {
      return false;
    }
    for (var i = 0; i < htmlFragments.length; i += 1) {
      if (htmlFragments[i] != other.htmlFragments[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(converterId, optionsSignature, Object.hashAll(htmlFragments));
}
