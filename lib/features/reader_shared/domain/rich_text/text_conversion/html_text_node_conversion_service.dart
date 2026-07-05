import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

abstract interface class HtmlTextNodeConversionService {
  Future<HtmlTextNodeConversionResult> convert({
    required String html,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
  });
}

final class DomHtmlTextNodeConversionService
    implements HtmlTextNodeConversionService {
  DomHtmlTextNodeConversionService({int maxCacheEntries = 8})
    : _maxCacheEntries = maxCacheEntries;

  static const String _delimiter =
      '\uE000\uE001y300-html-text-node\uE001\uE000';

  final int _maxCacheEntries;
  final _cache =
      <_HtmlTextNodeConversionCacheKey, HtmlTextNodeConversionResult>{};

  @override
  Future<HtmlTextNodeConversionResult> convert({
    required String html,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
  }) async {
    if (converter.mode == TextConversionMode.none || html.isEmpty) {
      return HtmlTextNodeConversionResult(
        html: html,
        convertedTextNodeCount: 0,
        converterId: converter.id,
      );
    }

    final key = _HtmlTextNodeConversionCacheKey(
      html: html,
      converterId: converter.id,
      optionsSignature: options.signature,
    );
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }

    final result = await _convertUncached(
      html: html,
      converter: converter,
      options: options,
    );
    _putCache(key, result);
    return result;
  }

  Future<HtmlTextNodeConversionResult> _convertUncached({
    required String html,
    required TextConverter converter,
    required HtmlTextNodeConversionOptions options,
  }) async {
    final fragment = html_parser.parseFragment(html);
    final textNodes = <html_dom.Text>[];
    for (final node in fragment.nodes) {
      _collectConvertibleTextNodes(node, options, textNodes);
    }

    if (textNodes.isEmpty) {
      return HtmlTextNodeConversionResult(
        html: html,
        convertedTextNodeCount: 0,
        converterId: converter.id,
      );
    }

    final values = [for (final node in textNodes) node.data];
    final convertedValues = values.any((value) => value.contains(_delimiter))
        ? await _convertIndividually(converter, values)
        : await _convertInBatch(converter, values);

    for (var i = 0; i < textNodes.length; i += 1) {
      textNodes[i].data = convertedValues[i];
    }

    return HtmlTextNodeConversionResult(
      html: _serializeFragment(fragment),
      convertedTextNodeCount: textNodes.length,
      converterId: converter.id,
    );
  }

  void _collectConvertibleTextNodes(
    html_dom.Node node,
    HtmlTextNodeConversionOptions options,
    List<html_dom.Text> output,
  ) {
    if (node is html_dom.Text) {
      if (node.data.trim().isNotEmpty && !_isInsideSkippedNode(node, options)) {
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

  bool _isInsideSkippedNode(
    html_dom.Node node,
    HtmlTextNodeConversionOptions options,
  ) {
    html_dom.Node? current = node.parentNode;
    while (current != null) {
      if (current is html_dom.Element && _shouldSkipElement(current, options)) {
        return true;
      }
      current = current.parentNode;
    }
    return false;
  }

  bool _shouldSkipElement(
    html_dom.Element element,
    HtmlTextNodeConversionOptions options,
  ) {
    final tagName = element.localName?.toLowerCase();
    if (tagName != null && options.skipTags.contains(tagName)) {
      return true;
    }
    return element.classes.any(options.skipClassNames.contains);
  }

  Future<List<String>> _convertInBatch(
    TextConverter converter,
    List<String> values,
  ) async {
    final converted = await converter.convertHtml(values.join(_delimiter));
    final parts = converted.split(_delimiter);
    if (parts.length == values.length) {
      return parts;
    }
    return _convertIndividually(converter, values);
  }

  Future<List<String>> _convertIndividually(
    TextConverter converter,
    List<String> values,
  ) {
    return Future.wait(values.map(converter.convertHtml));
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
    HtmlTextNodeConversionResult result,
  ) {
    if (_maxCacheEntries <= 0) {
      return;
    }
    _cache[key] = result;
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}

final htmlTextNodeConversionServiceProvider =
    Provider<HtmlTextNodeConversionService>(
      (ref) => DomHtmlTextNodeConversionService(),
    );

final class HtmlTextNodeConversionOptions {
  const HtmlTextNodeConversionOptions({
    this.skipTags = const {'script', 'style', 'pre', 'code', 'textarea'},
    this.skipClassNames = const {'blockcode'},
  });

  final Set<String> skipTags;
  final Set<String> skipClassNames;

  String get signature {
    final tags = skipTags.map((value) => value.toLowerCase()).toList()..sort();
    final classes = skipClassNames.toList()..sort();
    return 'skipTags=${tags.join(',')};skipClasses=${classes.join(',')}';
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

final class _HtmlTextNodeConversionCacheKey {
  const _HtmlTextNodeConversionCacheKey({
    required this.html,
    required this.converterId,
    required this.optionsSignature,
  });

  final String html;
  final String converterId;
  final String optionsSignature;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _HtmlTextNodeConversionCacheKey &&
            html == other.html &&
            converterId == other.converterId &&
            optionsSignature == other.optionsSignature;
  }

  @override
  int get hashCode => Object.hash(html, converterId, optionsSignature);
}
