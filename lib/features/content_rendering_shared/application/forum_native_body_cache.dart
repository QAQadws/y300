import 'package:forum_content_renderer/forum_content_renderer.dart';

/// Completed input and native glyph reuse for one browsing page. In-flight
/// work remains in the preparation scheduler; mounted views own their leases.
/// This cache never owns a Host, callback, Widget or reading session.
final class ForumNativeBodyCache {
  ForumNativeBodyCache({
    this.maxDocuments = 64,
    this.maxDocumentEstimatedBytes = 4 << 20,
    int maxParagraphEntries = 384,
    int maxParagraphEstimatedBytes = 24 << 20,
  }) : paragraphs = ForumBodyParagraphCache(
         maxEntries: maxParagraphEntries,
         maxEstimatedBytes: maxParagraphEstimatedBytes,
       ) {
    if (maxDocuments <= 0 || maxDocumentEstimatedBytes <= 0) {
      throw ArgumentError('Invalid body input cache budget');
    }
  }

  final int maxDocuments, maxDocumentEstimatedBytes;
  final ForumBodyParagraphCache paragraphs;
  final _documents = <(bool, Object), ({Object value, int bytes})>{};
  var _bytes = 0;
  var _documentHits = 0;
  var _preparedHits = 0;
  bool _closed = false;

  bool get isClosed => _closed;
  int get documentCount => _documents.length;
  int get documentEstimatedBytes => _bytes;
  int get documentHits => _documentHits;
  int get preparedHits => _preparedHits;

  ForumBodyDocument? documentFor(Object identity) {
    final value = _find((false, identity));
    if (value == null) return null;
    _documentHits++;
    return value as ForumBodyDocument;
  }

  ForumHtmlPreparedRenderDocument? preparedFor(Object identity) {
    final value = _find((true, identity));
    if (value == null) return null;
    _preparedHits++;
    return value as ForumHtmlPreparedRenderDocument;
  }

  void rememberDocument(
    Object identity,
    ForumBodyDocument document, {
    required int codeUnits,
  }) => _remember(
    (false, identity),
    document,
    1024 + codeUnits * 6 + document.parsedNodeCount * 192,
  );

  void rememberPrepared(
    Object identity,
    ForumHtmlPreparedRenderDocument document, {
    required int codeUnits,
  }) => _remember(
    (true, identity),
    document,
    1024 + (codeUnits + document.preparedHtml.length) * 4,
  );

  Object? _find((bool, Object) key) {
    if (_closed) return null;
    final entry = _documents.remove(key);
    if (entry != null) _documents[key] = entry;
    return entry?.value;
  }

  void _remember((bool, Object) key, Object value, int bytes) {
    if (_closed) return;
    final old = _documents.remove(key);
    _bytes -= old?.bytes ?? 0;
    // Large visible documents remain owned by their consumer, rather than
    // evicting the entire useful input working set just to retain one item.
    if (bytes > maxDocumentEstimatedBytes) return;
    _documents[key] = (value: value, bytes: bytes);
    _bytes += bytes;
    while (_documents.length > maxDocuments ||
        _bytes > maxDocumentEstimatedBytes) {
      _bytes -= _documents.remove(_documents.keys.first)!.bytes;
    }
  }

  /// Memory pressure drops reusable data and unpinned native layouts. Actual
  /// visible/neighbor leases stay valid until their consumers release them.
  void trim() {
    _documents.clear();
    _bytes = 0;
    paragraphs.clearUnpinned();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    trim();
    paragraphs.close();
  }
}
