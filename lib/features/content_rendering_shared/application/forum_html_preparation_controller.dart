import 'package:flutter/foundation.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'forum_html_preparation_executor.dart';
import 'forum_preparation_consumer.dart';
import 'forum_native_body_cache.dart';

/// A mounted consumer owns its document and rejects retired asynchronous work.
final class ForumHtmlPreparationController extends ChangeNotifier {
  ForumHtmlPreparationController({ForumHtmlPreparationExecutor? executor})
    : _executor = executor ?? ForumHtmlPreparationExecutor.shared {
    _consumer = ForumPreparationConsumer<ForumHtmlPreparedRenderDocument>(
      _executor,
    )..addListener(notifyListeners);
  }

  final ForumHtmlPreparationExecutor _executor;
  late final ForumPreparationConsumer<ForumHtmlPreparedRenderDocument>
  _consumer;
  bool _closed = false;
  ForumNativeBodyCache? _cache;
  ForumHtmlPreparedRenderDocument? _document;

  Object? get identity => _consumer.identity;
  bool get hasError => _consumer.hasError;

  ForumHtmlPreparedRenderDocument? resolve(
    ForumHtmlPreparationRequest request, {
    ForumNativeBodyCache? cache,
    ({Object identity, ForumHtmlPreparedRenderDocument document})? seed,
  }) {
    if (!identical(_cache, cache)) {
      _consumer.reset();
      _document = null;
      _cache = cache;
    }
    if (seed?.identity == request.identity &&
        !identical(_document, seed!.document)) {
      // A transferred source references this exact prepared document. Replace
      // an equivalent earlier value once, then keep that accepted value stable.
      _consumer.reset();
    }
    final cached = seed?.identity == request.identity
        ? seed!.document
        : cache?.preparedFor(request.identity);
    final document = _consumer.resolve(
      identity: request.identity,
      admit: () => _executor.tryAcquire(request),
      prepareSynchronously: cached != null
          ? () => cached
          : _executor.usesBackground(request)
          ? null
          : request.prepareSynchronously,
    );
    if (document != null) {
      _document = document;
      cache?.rememberPrepared(
        request.identity,
        document,
        codeUnits: request.html.length,
      );
    }
    return document;
  }

  void reset() {
    _document = null;
    _consumer.reset();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _document = null;
    _consumer.dispose();
    super.dispose();
  }
}
