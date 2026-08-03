import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/discuz_ajax_cdata_parser.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';

final class ComposerUnusedImageParser {
  const ComposerUnusedImageParser({
    this.cdataParser = const DiscuzAjaxCdataParser(),
  });

  final DiscuzAjaxCdataParser cdataParser;

  List<ComposerUnusedImage> parse({
    required String body,
    required Uri sourceUri,
    required bool hasConfirmedLoggedInSession,
  }) {
    final siteUri = Uri.parse(AppConfig.siteBaseUrl);
    if (!_isExpectedCatalogUri(sourceUri, siteUri)) {
      throw const FormatException('Unexpected attachment catalog location');
    }
    final payload = cdataParser.extract(body);
    if (payload == null) {
      throw const FormatException('Missing Discuz AJAX CDATA envelope');
    }
    if (payload.trim().isEmpty) {
      if (!hasConfirmedLoggedInSession) {
        throw const FormatException(
          'Empty attachment catalog without a confirmed session',
        );
      }
      return const <ComposerUnusedImage>[];
    }

    final fragment = html_parser.parseFragment(payload);
    final hasUnexpectedText = fragment.nodes.whereType<Text>().any(
      (node) => node.data.trim().isNotEmpty,
    );
    if (hasUnexpectedText ||
        fragment.children.length != 1 ||
        fragment.children.single.localName != 'table' ||
        !fragment.children.single.classes.contains('imgl')) {
      throw const FormatException('Unexpected attachment catalog structure');
    }
    final cells = fragment.querySelectorAll('td');
    final imageCells = cells
        .where((cell) {
          return (cell.id).startsWith('image_td_');
        })
        .toList(growable: false);
    if (imageCells.isEmpty) {
      if (_isKnownEmptyCatalog(fragment, cells) &&
          hasConfirmedLoggedInSession) {
        return const <ComposerUnusedImage>[];
      }
      throw const FormatException('Missing unused attachment cells');
    }

    for (final cell in cells) {
      if (cell.id.startsWith('image_td_')) {
        continue;
      }
      if (cell.text.trim().isNotEmpty || cell.querySelector('img') != null) {
        throw const FormatException('Unexpected attachment catalog cell');
      }
    }

    final byAid = <String, ComposerUnusedImage>{};
    for (final cell in imageCells) {
      final aid = cell.id.substring('image_td_'.length).trim();
      if (!_isPositiveInteger(aid)) {
        throw const FormatException('Invalid unused attachment aid');
      }
      final images = cell.querySelectorAll('img[src]');
      if (images.length != 1) {
        throw const FormatException('Invalid unused attachment image');
      }
      if (images.single.id != 'image_$aid') {
        throw const FormatException('Mismatched unused attachment image');
      }
      final attachmentAnchors = cell.querySelectorAll('#imageattach$aid');
      if (attachmentAnchors.length != 1) {
        throw const FormatException('Invalid unused attachment metadata');
      }
      final descriptionInputs = cell.querySelectorAll(
        'input[name="attachnew[$aid][description]"]',
      );
      if (descriptionInputs.length > 1) {
        throw const FormatException('Conflicting attachment description');
      }
      final rawSource = images.single.attributes['src']?.trim() ?? '';
      final thumbnailUri = _resolveSameOriginImage(
        rawSource,
        sourceUri: sourceUri,
        expectedAid: aid,
      );
      if (thumbnailUri == null) {
        throw const FormatException('Unsafe unused attachment image URL');
      }
      final title = attachmentAnchors.single.attributes['title']?.trim() ?? '';
      final description = descriptionInputs.isEmpty
          ? ''
          : descriptionInputs.single.attributes['value']?.trim() ?? '';
      final parsed = ComposerUnusedImage(
        aid: aid,
        thumbnailUri: thumbnailUri,
        fileName: title,
        description: description,
      );
      final previous = byAid[aid];
      if (previous != null) {
        if (previous.thumbnailUri != parsed.thumbnailUri ||
            previous.fileName != parsed.fileName ||
            previous.description != parsed.description) {
          throw const FormatException('Conflicting unused attachment aid');
        }
        continue;
      }
      byAid[aid] = parsed;
    }
    return List<ComposerUnusedImage>.unmodifiable(byAid.values);
  }

  bool _isKnownEmptyCatalog(DocumentFragment fragment, List<Element> cells) {
    if (cells.any(
      (cell) =>
          cell.text.trim().isNotEmpty || cell.querySelector('img') != null,
    )) {
      return false;
    }
    final tables = fragment.querySelectorAll('table');
    return tables.length == 1 && tables.single.classes.contains('imgl');
  }

  Uri? _resolveSameOriginImage(
    String raw, {
    required Uri sourceUri,
    required String expectedAid,
  }) {
    if (raw.isEmpty) {
      return null;
    }
    final decoded = raw.replaceAll('&amp;', '&');
    final parsed = Uri.tryParse(decoded);
    if (parsed == null) {
      return null;
    }
    final resolved = sourceUri.resolveUri(parsed);
    if (!_isSameOrigin(resolved, sourceUri) ||
        resolved.path != '/forum.php' ||
        resolved.queryParameters['mod'] != 'image' ||
        resolved.queryParameters['aid'] != expectedAid) {
      return null;
    }
    return resolved;
  }

  bool _isSameOrigin(Uri left, Uri right) {
    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        left.port == right.port;
  }

  bool _isExpectedCatalogUri(Uri sourceUri, Uri siteUri) {
    return _isSameOrigin(sourceUri, siteUri) &&
        sourceUri.path == '/forum.php' &&
        sourceUri.queryParameters['mod'] == 'ajax' &&
        sourceUri.queryParameters['action'] == 'imagelist' &&
        sourceUri.queryParameters['posttime'] == '0';
  }

  bool _isPositiveInteger(String value) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed > 0 && parsed.toString() == value;
  }
}
