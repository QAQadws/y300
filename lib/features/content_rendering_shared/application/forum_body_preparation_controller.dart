import 'package:flutter/foundation.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'forum_body_preparation_executor.dart';
import 'forum_preparation_consumer.dart';
import 'forum_native_body_cache.dart';

/// One display owner accepts only its latest native document preparation.
/// Reset/dispose releases queued work without cancelling another consumer.
final class ForumBodyPreparationController extends ChangeNotifier {
  ForumBodyPreparationController({ForumBodyPreparationExecutor? executor})
    : _executor = executor ?? ForumBodyPreparationExecutor.shared {
    _consumer = ForumPreparationConsumer<ForumBodyDocument>(_executor)
      ..addListener(notifyListeners);
  }

  final ForumBodyPreparationExecutor _executor;
  late final ForumPreparationConsumer<ForumBodyDocument> _consumer;
  bool _closed = false;
  ForumNativeBodyCache? _cache;

  bool get hasError => _consumer.hasError;

  ForumBodyDocument? resolve(
    ForumBodyPreparationInput input, {
    required Object owner,
    ForumNativeBodyCache? cache,
  }) {
    if (!identical(_cache, cache)) {
      _consumer.reset();
      _cache = cache;
    }
    final cached = cache?.documentFor(input.identity);
    final document = _consumer.resolve(
      identity: (owner, input.identity),
      admit: () => _executor.tryAcquire(input),
      prepareSynchronously: cached != null
          ? () => cached
          : _executor.usesBackground(input)
          ? null
          : input.prepareSynchronously,
    );
    if (document != null) {
      cache?.rememberDocument(
        input.identity,
        document,
        codeUnits: input.html.length,
      );
    }
    return document;
  }

  void reset() => _consumer.reset();

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _consumer.dispose();
    super.dispose();
  }
}
